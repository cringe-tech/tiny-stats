import Foundation
import SMCKit

/// Single shared polling loop for all metrics. Battery-friendly by design:
/// one timer on a utility queue (not one per widget), a settable interval, and SMC
/// sensors are only read when a consumer actually needs them.
///
/// `@unchecked Sendable`: all mutable state is confined to `queue`; the public surface
/// either hops onto it or is set-once before `start`.
public final class MetricsEngine: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.tinystats.metrics", qos: .utility)
    private var timer: DispatchSourceTimer?

    private let cpu = CPUCollector()
    private let memory = MemoryCollector()
    private let network = NetworkCollector()
    private let disk = DiskCollector()
    private let gpu = GPUCollector()
    private let battery = BatteryCollector()
    private let sensors = SMCSensors()
    private let processes = ProcessSampler()

    /// Fresh snapshots are delivered here; consume with `for await`.
    public let snapshots: AsyncStream<MetricsSnapshot>
    private let continuation: AsyncStream<MetricsSnapshot>.Continuation

    private var interval: TimeInterval = 3
    private var includeSensors = false
    private var includeProcesses = false
    private var enabledKinds: Set<MetricKind> = Set(MetricKind.allCases)

    public init() {
        var cont: AsyncStream<MetricsSnapshot>.Continuation!
        snapshots = AsyncStream(bufferingPolicy: .bufferingNewest(1)) { cont = $0 }
        continuation = cont
    }

    public func start(interval: TimeInterval) {
        queue.async { [self] in scheduleTimer(interval: interval) }
    }

    public func setInterval(_ interval: TimeInterval) {
        queue.async { [self] in
            guard self.interval != interval else { return }
            scheduleTimer(interval: interval)
        }
    }

    /// SMC reads are skipped unless a consumer (the sensors view) needs them.
    public func setIncludeSensors(_ include: Bool) {
        queue.async { [self] in includeSensors = include }
    }

    /// Per-process sampling is skipped unless a consumer (the overview) needs it.
    public func setIncludeProcesses(_ include: Bool) {
        queue.async { [self] in includeProcesses = include }
    }

    /// Restricts which optional collectors run, so hidden metrics gather no data.
    public func setEnabledMetrics(_ kinds: Set<MetricKind>) {
        queue.async { [self] in enabledKinds = kinds }
    }

    public func stop() {
        queue.async { [self] in
            timer?.cancel()
            timer = nil
        }
    }

    /// Forces an immediate sample (e.g. right when the popover opens).
    public func refreshNow() {
        queue.async { [self] in tick() }
    }

    private func scheduleTimer(interval: TimeInterval) {
        self.interval = interval
        timer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(500))
        timer.setEventHandler { [self] in tick() }
        self.timer = timer
        timer.resume()
    }

    private func tick() {
        var snapshot = MetricsSnapshot()
        snapshot.cpu = cpu.sample()
        snapshot.memory = memory.sample()
        if enabledKinds.contains(.network) { snapshot.network = network.sample() }
        if enabledKinds.contains(.disk) { snapshot.disk = disk.sample() }
        if enabledKinds.contains(.gpu) { snapshot.gpu = gpu.sample() }
        if enabledKinds.contains(.battery) { snapshot.battery = battery.sample() }
        if includeSensors, let sensors {
            snapshot.sensors = sensors.readAll()
        }
        if includeProcesses {
            snapshot.processes = processes.sample()
        }
        continuation.yield(snapshot)
    }
}
