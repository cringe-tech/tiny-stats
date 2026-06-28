import Foundation
import SMCKit
import FanControlShared

// Privileged fan-control daemon. Runs as root via a LaunchDaemon and is the ONLY code that
// writes SMC fan keys. The user app talks to it over XPC; all hardware-safety rules live here
// (clamp to [min,max], watchdog revert-to-auto), so even an untrusted caller can't drive the
// fans outside safe limits or leave them stuck forced.

/// Serial queue owning the SMC connection and all mutable state, so concurrent XPC calls and
/// the watchdog never race on the hardware. The class is `@unchecked Sendable` on that promise.
final class HelperService: NSObject, FanHelperProtocol, NSXPCListenerDelegate, @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.tinystats.fanhelper.smc")
    private let smc: SMCConnection
    private let fanCount: Int
    private var controlActive = false
    private var lastHeartbeat = Date()
    private var watchdog: DispatchSourceTimer?

    /// Opens the SMC and builds the service, or returns nil if AppleSMC is unavailable.
    /// A factory (not a failable `init?`) so it doesn't clash with `NSObject.init()`.
    static func create() -> HelperService? {
        guard let smc = SMCConnection() else { return nil }
        return HelperService(smc: smc)
    }

    private init(smc: SMCConnection) {
        self.smc = smc
        self.fanCount = Int(smc.read("FNum")?.double ?? 0)
        super.init()
        startWatchdog()
    }

    // MARK: NSXPCListenerDelegate

    func listener(_ listener: NSXPCListener,
                  shouldAcceptNewConnection conn: NSXPCConnection) -> Bool {
        conn.exportedInterface = NSXPCInterface(with: FanHelperProtocol.self)
        conn.exportedObject = self
        // If the client goes away (quit, crash, killed) the connection invalidates — fail safe.
        conn.invalidationHandler = { [weak self] in
            guard let self else { return }
            self.queue.async { _ = self.revertAllToAuto() }
        }
        conn.resume()
        return true
    }

    // MARK: FanHelperProtocol

    func info(reply: @escaping @Sendable (Data?) -> Void) {
        queue.async { [self] in
            var fans: [FanInfo] = []
            for i in 0..<fanCount {
                fans.append(FanInfo(
                    index: i,
                    minRPM: smc.read("F\(i)Mn")?.double ?? 0,
                    maxRPM: smc.read("F\(i)Mx")?.double ?? 0,
                    actualRPM: smc.read("F\(i)Ac")?.double ?? 0,
                    mode: Int(smc.read("F\(i)Md")?.double ?? 0)))
            }
            let info = FanHelperInfo(protocolVersion: FanHelper.protocolVersion, fans: fans)
            reply(try? JSONEncoder().encode(info))
        }
    }

    func setTarget(fan index: Int, rpm: Double, reply: @escaping @Sendable (Bool) -> Void) {
        queue.async { [self] in
            guard index >= 0, index < fanCount else { reply(false); return }
            // Clamp helper-side: never below the fan's reported minimum, never above its max.
            let mn = smc.read("F\(index)Mn")?.double ?? 0
            let mx = smc.read("F\(index)Mx")?.double ?? rpm
            let clamped = Swift.min(Swift.max(rpm, mn), mx)
            let okMode = smc.write("F\(index)Md", value: 1)
            let okTarget = smc.write("F\(index)Tg", value: clamped)
            controlActive = true
            lastHeartbeat = Date()
            reply(okMode && okTarget)
        }
    }

    func setAuto(fan index: Int, reply: @escaping @Sendable (Bool) -> Void) {
        queue.async { [self] in
            guard index >= 0, index < fanCount else { reply(false); return }
            reply(smc.write("F\(index)Md", value: 0))
        }
    }

    func setAutoAll(reply: @escaping @Sendable (Bool) -> Void) {
        queue.async { [self] in reply(self.revertAllToAuto()) }
    }

    func heartbeat(reply: @escaping @Sendable (Bool) -> Void) {
        queue.async { [self] in
            lastHeartbeat = Date()
            reply(true)
        }
    }

    // MARK: Safety

    /// Hands every fan back to system (auto) control. Must be called on `queue`.
    @discardableResult
    private func revertAllToAuto() -> Bool {
        var ok = true
        for i in 0..<fanCount where !smc.write("F\(i)Md", value: 0) { ok = false }
        controlActive = false
        return ok
    }

    /// Synchronous revert for the SIGTERM path (launchd unload), so we don't exit mid-write.
    func revertAllToAutoSync() {
        queue.sync { _ = revertAllToAuto() }
    }

    /// Reverts to auto if the app stops heartbeating — covers a crashed/hung/force-killed app
    /// whose connection didn't cleanly invalidate.
    private func startWatchdog() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 2, repeating: 2)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            if self.controlActive,
               Date().timeIntervalSince(self.lastHeartbeat) > FanHelper.watchdogSeconds {
                _ = self.revertAllToAuto()
            }
        }
        timer.resume()
        watchdog = timer
    }
}

// MARK: - Entry point

guard let service = HelperService.create() else {
    FileHandle.standardError.write(Data("fanhelper: cannot open AppleSMC\n".utf8))
    exit(1)
}

// Revert to auto on launchd unload (SIGTERM) before exiting, so quitting/uninstalling the
// helper never leaves fans stuck in forced mode.
signal(SIGTERM, SIG_IGN)
let termSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
termSource.setEventHandler {
    service.revertAllToAutoSync()
    exit(0)
}
termSource.resume()

let listener = NSXPCListener(machServiceName: FanHelper.machServiceName)
listener.delegate = service
listener.resume()
dispatchMain()
