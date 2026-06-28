import Foundation
import SMCKit
import FanControlShared

// App-side fan-control engine. Reads the chosen temperature sensor on its own cadence
// (independent of the UI refresh interval, so thermal responsiveness never depends on display
// settings), evaluates the active curve, and asks the privileged helper to set fan targets.
// The helper owns all hardware safety; this side adds a critical-temperature hard cutoff and a
// steady heartbeat so the helper's watchdog can fail safe if this process dies.

/// What the controller should be doing right now. Pushed in from settings.
public struct FanControlConfig: Equatable, Sendable {
    public var enabled: Bool
    public var preset: FanPreset
    public var sensorSource: FanSensorSource
    public var customCurve: FanCurve
    /// At or above this temperature the controller hands fans back to the system, regardless
    /// of the curve — a last-resort thermal safety net.
    public var hardCutoffC: Double

    public init(enabled: Bool = false, preset: FanPreset = .auto,
                sensorSource: FanSensorSource = .cpu,
                customCurve: FanCurve = FanModel.defaultCustomCurve,
                hardCutoffC: Double = 95) {
        self.enabled = enabled
        self.preset = preset
        self.sensorSource = sensorSource
        self.customCurve = customCurve
        self.hardCutoffC = hardCutoffC
    }

    /// The curve currently in effect, or nil when fans should be left to the system (`.auto`).
    var activeCurve: FanCurve? {
        guard enabled else { return nil }
        switch preset {
        case .auto: return nil
        case .custom: return customCurve
        default: return preset.builtInCurve
        }
    }
}

/// Live status the UI observes.
public struct FanControlStatus: Equatable, Sendable {
    public var helperInstalled = false
    public var helperResponding = false
    public var fans: [FanInfo] = []
    public var sourceTempC: Double?
    public var appliedPercent: Double?
    /// Name of a detected third-party fan controller (e.g. "Macs Fan Control"), if any —
    /// surfaced as a warning since two controllers fight over the same SMC keys.
    public var conflict: String?
    public var lastError: String?

    public init() {}
}

/// Confined to `queue` (SMC + XPC), like `MetricsEngine`; status is published on the main actor.
public final class FanController: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.tinystats.fancontrol", qos: .utility)
    private let sensors = SMCSensors()
    private var smc: SMCConnection?
    private var xpc: NSXPCConnection?
    private var timer: DispatchSourceTimer?
    private var config = FanControlConfig()
    private var status = FanControlStatus()

    /// Called on the main actor whenever status changes, so `AppState` can republish to SwiftUI.
    private let onStatus: @MainActor (FanControlStatus) -> Void

    /// Control loop period. Short enough to react to heat, well inside the helper's watchdog.
    private let tickInterval: TimeInterval = 2

    public init(onStatus: @escaping @MainActor (FanControlStatus) -> Void) {
        self.onStatus = onStatus
    }

    // MARK: Public API (called from the main actor)

    /// Pushes a new desired configuration and (re)starts or stops the loop accordingly.
    public func apply(_ newConfig: FanControlConfig) {
        queue.async { [self] in
            let was = config.enabled
            config = newConfig
            if newConfig.enabled, !was {
                startLoop()
            } else if !newConfig.enabled, was {
                stopLoop(revertToAuto: true)
            } else if newConfig.enabled {
                tick()   // apply preset/sensor change immediately
            }
        }
    }

    /// Installs the privileged helper (one admin-password prompt). Updates status on return.
    public func installHelper() async -> Result<Void, HelperError> {
        await withCheckedContinuation { (cont: CheckedContinuation<Result<Void, HelperError>, Never>) in
            queue.async { [self] in
                let result = HelperInstaller.install()
                status.helperInstalled = HelperInstaller.isInstalled
                publish()
                cont.resume(returning: result)
            }
        }
    }

    /// Reverts fans to auto, then removes the helper (one admin-password prompt).
    public func uninstallHelper() async -> Result<Void, HelperError> {
        await withCheckedContinuation { (cont: CheckedContinuation<Result<Void, HelperError>, Never>) in
            queue.async { [self] in
                if let proxy = proxy() { proxy.setAutoAll { _ in } }
                stopLoop(revertToAuto: false)
                xpc?.invalidate()
                xpc = nil
                let result = HelperInstaller.uninstall()
                status.helperInstalled = HelperInstaller.isInstalled
                status.helperResponding = false
                publish()
                cont.resume(returning: result)
            }
        }
    }

    /// Refreshes installed status without controlling (e.g. when Settings opens). Conflict
    /// detection is owned by the app layer (it needs the running-app list), not here.
    public func refreshStatus() {
        queue.async { [self] in
            status.helperInstalled = HelperInstaller.isInstalled
            publish()
        }
    }

    // MARK: Loop

    private func startLoop() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: tickInterval, leeway: .milliseconds(300))
        t.setEventHandler { [weak self] in self?.tick() }
        timer = t
        t.resume()
    }

    private func stopLoop(revertToAuto: Bool) {
        timer?.cancel()
        timer = nil
        if revertToAuto, let proxy = proxy() {
            proxy.setAutoAll { _ in }
        }
        status.appliedPercent = nil
        status.sourceTempC = nil
        publish()
    }

    private func tick() {
        status.helperInstalled = HelperInstaller.isInstalled

        let readings = sensors?.readAll() ?? []
        let temp = FanModel.sourceTemperature(from: readings, source: config.sensorSource)
        status.sourceTempC = temp

        guard let proxy = proxy() else {
            status.helperResponding = false
            status.appliedPercent = nil
            publish()
            return
        }

        // Pull live fan limits/RPM, then decide and apply within the reply. We re-fetch the proxy
        // inside the queue rather than capture it (XPC proxies aren't Sendable).
        proxy.info { [weak self] data in
            guard let self else { return }
            self.queue.async {
                if let data, let info = try? JSONDecoder().decode(FanHelperInfo.self, from: data),
                   let proxy = self.proxy() {
                    self.status.helperResponding = true
                    self.status.fans = info.fans
                    self.applyControl(temp: temp, fans: info.fans, proxy: proxy)
                } else {
                    self.status.helperResponding = false
                    self.status.appliedPercent = nil
                }
                self.publish()
            }
        }
    }

    /// Decides the target for each fan and sends it, or hands back to auto. Runs on `queue`.
    private func applyControl(temp: Double?, fans: [FanInfo], proxy: FanHelperProtocol) {
        // No curve (auto preset) → release fans to the system.
        guard let curve = config.activeCurve else {
            proxy.setAutoAll { _ in }
            status.appliedPercent = nil
            return
        }
        // Critical-temperature hard cutoff: hand back to the system so firmware can do its job.
        if let t = temp, t >= config.hardCutoffC {
            proxy.setAutoAll { _ in }
            status.appliedPercent = nil
            status.lastError = nil
            return
        }
        guard let t = temp else {
            // No temperature reading — don't guess; release to system.
            proxy.setAutoAll { _ in }
            status.appliedPercent = nil
            return
        }
        let percent = curve.percent(atTemp: t)
        status.appliedPercent = percent
        for fan in fans {
            let rpm = FanModel.rpm(forPercent: percent, min: fan.minRPM, max: fan.maxRPM)
            proxy.setTarget(fan: fan.index, rpm: rpm) { _ in }
        }
        proxy.heartbeat { _ in }
    }

    // MARK: XPC

    private func connection() -> NSXPCConnection {
        if let xpc { return xpc }
        let c = NSXPCConnection(machServiceName: FanHelper.machServiceName, options: .privileged)
        c.remoteObjectInterface = NSXPCInterface(with: FanHelperProtocol.self)
        let drop: @Sendable () -> Void = { [weak self] in
            guard let self else { return }
            self.queue.async { self.xpc = nil }
        }
        c.invalidationHandler = drop
        c.interruptionHandler = drop
        c.resume()
        xpc = c
        return c
    }

    private func proxy() -> FanHelperProtocol? {
        guard HelperInstaller.isInstalled else { return nil }
        return connection().remoteObjectProxyWithErrorHandler { [weak self] error in
            guard let self else { return }
            self.queue.async {
                self.status.helperResponding = false
                self.status.lastError = error.localizedDescription
            }
        } as? FanHelperProtocol
    }

    private func publish() {
        let snapshot = status
        Task { @MainActor in self.onStatus(snapshot) }
    }
}
