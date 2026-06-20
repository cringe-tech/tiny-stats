import Foundation
import SwiftUI
import ServiceManagement
import TinyStatsCore

/// Single source of truth for metric colours, so the menu-bar cells, Overview, History and
/// Settings all stay in sync. Two colour axes that must not be confused:
///   • per-resource tints (`cpu`/`gpu`/… below) identify *which* metric a row belongs to;
///   • `ingress`/`egress` colour the two directions of a paired flow, grouped by data
///     direction relative to the machine: data coming in / being stored (network download,
///     disk write) vs data going out / being read (network upload, disk read).
/// Disk is deliberately `brown` for its section tint, not orange.
enum Palette {
    static let cpu = Color.blue
    static let gpu = Color.purple
    static let memory = Color.indigo
    static let network = Color.teal
    static let disk = Color.brown
    static let battery = Color.green

    /// Flow direction, grouped by ingress/egress (see above).
    static let ingress = Color.teal     // network download / disk write
    static let egress = Color.orange    // network upload / disk read
}

/// A metric that can be shown as a cell in the menu bar.
enum BarMetric: String, CaseIterable, Identifiable, Codable {
    case cpu, gpu, memory, network, disk, battery
    var id: String { rawValue }
    var label: String {
        switch self {
        case .cpu: return Loc.t(.cpu)
        case .gpu: return Loc.t(.gpu)
        case .memory: return Loc.t(.memory)
        case .network: return Loc.t(.network)
        case .disk: return Loc.t(.disk)
        case .battery: return Loc.t(.battery)
        }
    }
    var symbol: String {
        switch self {
        case .cpu: return "cpu"
        case .gpu: return "cpu.fill"
        case .memory: return "memorychip"
        case .network: return "network"
        case .disk: return "internaldrive"
        case .battery: return "battery.100"
        }
    }
    var tint: Color {
        switch self {
        case .cpu: return Palette.cpu
        case .gpu: return Palette.gpu
        case .memory: return Palette.memory
        case .network: return Palette.network
        case .disk: return Palette.disk
        case .battery: return Palette.battery
        }
    }
}

/// A section that appears in Overview and History, with a configurable order.
enum OverviewSection: String, CaseIterable, Identifiable, Codable {
    case cpu, memory, network, disk, gpu, battery
    var id: String { rawValue }
    var label: String {
        switch self {
        case .cpu: return Loc.t(.cpu)
        case .memory: return Loc.t(.memory)
        case .network: return Loc.t(.network)
        case .disk: return Loc.t(.disk)
        case .gpu: return Loc.t(.gpu)
        case .battery: return Loc.t(.battery)
        }
    }
    var symbol: String {
        switch self {
        case .cpu: return "cpu"
        case .memory: return "memorychip"
        case .network: return "network"
        case .disk: return "internaldrive"
        case .gpu: return "cpu.fill"
        case .battery: return "battery.100"
        }
    }
    var tint: Color {
        switch self {
        case .cpu: return Palette.cpu
        case .memory: return Palette.memory
        case .network: return Palette.network
        case .disk: return Palette.disk
        case .gpu: return Palette.gpu
        case .battery: return Palette.battery
        }
    }
}

/// Temperature display unit for sensors. `.system` follows the macOS region setting.
enum TemperatureUnit: String, CaseIterable, Identifiable, Codable {
    case system
    case celsius
    case fahrenheit
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return Loc.t(.system)
        case .celsius: return "°C"
        case .fahrenheit: return "°F"
        }
    }

    /// `.system` resolved against the current locale; others map to themselves.
    var resolved: TemperatureUnit {
        switch self {
        case .system:
            return Locale.current.measurementSystem == .us ? .fahrenheit : .celsius
        default:
            return self
        }
    }
}

/// How a menu-bar cell renders its number.
enum BarValueMode: String, CaseIterable, Identifiable, Codable {
    case percent
    case current
    var id: String { rawValue }
    var label: String {
        switch self {
        case .percent: return "Percent of max"
        case .current: return "Current value"
        }
    }
}

/// What a menu-bar cell shows: any combination of icon, label and value.
enum BarDisplayMode: String, CaseIterable, Identifiable, Codable {
    case iconValue
    case labelValue
    case valueOnly
    var id: String { rawValue }
    var label: String {
        switch self {
        case .iconValue: return Loc.t(.iconValue)
        case .labelValue: return Loc.t(.labelValue)
        case .valueOnly: return Loc.t(.valueOnly)
        }
    }
    var showsIcon: Bool { self == .iconValue }
    var showsLabel: Bool { self == .labelValue }
    var showsValue: Bool { true }
}

/// Valid history retention windows, in minutes.
enum HistoryRetention: Int, CaseIterable, Identifiable {
    case m1 = 1, m5 = 5, m15 = 15, m30 = 30, h1 = 60
    var id: Int { rawValue }
    var label: String {
        rawValue < 60 ? "\(rawValue) \(Loc.t(.minutesShort))" : "1 \(Loc.t(.hourShort))"
    }
}

/// User-facing configuration. Edited as a draft in Settings, then committed via `apply`.
struct AppSettings: Equatable, Codable {
    var barMetrics: [BarMetric] = [.cpu, .memory, .network]
    var barValueMode: BarValueMode = .percent
    var barDisplayMode: BarDisplayMode = .iconValue
    var baseInterval: Double = 10
    var launchAtLogin: Bool = true
    var nerdStats: Bool = false
    var temperatureUnit: TemperatureUnit = .system
    var language: AppLanguage = .system
    var topProcessCount: Int = 3
    var processListEnabled: Bool = true
    var showProcessesCPU: Bool = true
    var showProcessesMemory: Bool = true
    var showProcessesDisk: Bool = true
    var showHistoryTab: Bool = true
    var historyRetentionMinutes: Int = 5
    var autoCheckUpdates: Bool = true
    /// Sections shown in Overview/History, in order. Inactive ones gather no data.
    var overviewOrder: [OverviewSection] = [.cpu, .memory, .network, .disk, .gpu, .battery]
    var inactiveSections: [OverviewSection] = []

    // Custom init so that old saved settings (missing new keys) still load without resetting everything.
    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        barMetrics = (try? c.decode([BarMetric].self, forKey: .barMetrics)) ?? [.cpu, .memory, .network]
        barValueMode = (try? c.decode(BarValueMode.self, forKey: .barValueMode)) ?? .percent
        barDisplayMode = (try? c.decode(BarDisplayMode.self, forKey: .barDisplayMode)) ?? .iconValue
        baseInterval = (try? c.decode(Double.self, forKey: .baseInterval)) ?? 10
        launchAtLogin = (try? c.decode(Bool.self, forKey: .launchAtLogin)) ?? true
        nerdStats = (try? c.decode(Bool.self, forKey: .nerdStats)) ?? false
        temperatureUnit = (try? c.decode(TemperatureUnit.self, forKey: .temperatureUnit)) ?? .system
        language = (try? c.decode(AppLanguage.self, forKey: .language)) ?? .system
        topProcessCount = (try? c.decode(Int.self, forKey: .topProcessCount)) ?? 3
        processListEnabled = (try? c.decode(Bool.self, forKey: .processListEnabled)) ?? true
        showProcessesCPU = (try? c.decode(Bool.self, forKey: .showProcessesCPU)) ?? true
        showProcessesMemory = (try? c.decode(Bool.self, forKey: .showProcessesMemory)) ?? true
        showProcessesDisk = (try? c.decode(Bool.self, forKey: .showProcessesDisk)) ?? true
        showHistoryTab = (try? c.decode(Bool.self, forKey: .showHistoryTab)) ?? true
        historyRetentionMinutes = (try? c.decode(Int.self, forKey: .historyRetentionMinutes)) ?? 5
        autoCheckUpdates = (try? c.decode(Bool.self, forKey: .autoCheckUpdates)) ?? true
        overviewOrder = (try? c.decode([OverviewSection].self, forKey: .overviewOrder))
            ?? [.cpu, .memory, .network, .disk, .gpu, .battery]
        inactiveSections = (try? c.decode([OverviewSection].self, forKey: .inactiveSections)) ?? []
    }
}

/// One point of recorded history for the charts.
struct MetricSample: Identifiable {
    let id: Int
    let time: Date
    let cpu: Double
    let gpu: Double
    let memory: Double
    let netDown: Double
    let netUp: Double
    let battery: Double
    let diskRead: Double
    let diskWrite: Double
    let lowPower: Bool
}

/// Owns the metrics engine, the applied settings, and recorded history. Drives the
/// engine's interval adaptively from power state and popover visibility.
@MainActor
final class AppState: ObservableObject {
    @Published var snapshot = MetricsSnapshot()
    @Published private(set) var settings: AppSettings
    @Published private(set) var history: [MetricSample] = []
    @Published private(set) var updateStatus: UpdateStatus = .idle
    /// Leftmost menu-bar cells currently dropped because they don't fit beside the notch.
    @Published private(set) var menuBarHiddenCount = 0
    /// Whether macOS Low Power Mode is currently on (shown on the cells, Overview and History).
    @Published private(set) var lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
    private var lastUpdateCheck: Date?

    private let engine = MetricsEngine()
    private let menuBarFit = MenuBarFit()
    private var popoverVisible = false
    private var sampleCounter = 0
    /// Hard cap so memory stays bounded even at the longest retention / fastest interval.
    private let historyHardCap = 5000
    private static let defaultsKey = "appSettings"

    init() {
        Log.installCrashHandlers()
        Log.info("Launch — \(Self.launchInfo())")
        settings = Self.loadSettings() ?? AppSettings()
        Loc.language = settings.language
        engine.start(interval: settings.baseInterval)
        engine.setEnabledMetrics(neededMetricKinds())
        let stream = engine.snapshots
        Task { [weak self] in
            for await snap in stream {
                self?.ingest(snap)
            }
        }

        NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
                self?.recomputeInterval()
            }
        }
        menuBarFit.observe { [weak self] in self?.recomputeMenuBarFit() }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.recomputeMenuBarFit() }
        }
        recomputeInterval()
        syncLaunchAtLogin()
        if settings.autoCheckUpdates { checkForUpdates(force: false) }
    }

    // MARK: Updates

    /// Checks GitHub for a newer release. Throttled to once a day unless forced.
    func checkForUpdates(force: Bool) {
        guard UpdateChecker.isConfigured else { return }
        if !force, let last = lastUpdateCheck, Date().timeIntervalSince(last) < 24 * 3600 { return }
        lastUpdateCheck = Date()
        updateStatus = .checking
        Task { [weak self] in
            let status = await UpdateChecker.fetchLatest()
            self?.updateStatus = status
        }
    }

    private func ingest(_ snap: MetricsSnapshot) {
        snapshot = snap
        sampleCounter += 1
        history.append(MetricSample(
            id: sampleCounter, time: snap.date,
            cpu: snap.cpu.total, gpu: snap.gpu.utilization, memory: snap.memory.fraction,
            netDown: snap.network.downloadBytesPerSec, netUp: snap.network.uploadBytesPerSec,
            battery: snap.battery?.charge ?? 0,
            diskRead: snap.disk.readBytesPerSec, diskWrite: snap.disk.writeBytesPerSec,
            lowPower: lowPowerMode
        ))
        trimHistory(now: snap.date)
        // Re-measure on the next runloop tick, once the new label has been laid out in the bar.
        DispatchQueue.main.async { [weak self] in self?.recomputeMenuBarFit() }
    }

    /// Asks `MenuBarFit` how many leftmost cells to drop, and publishes the result so the
    /// menu-bar label and the Settings warning both update.
    private func recomputeMenuBarFit() {
        let n = menuBarFit.hiddenCount(metrics: settings.barMetrics, snapshot: snapshot,
                                       mode: settings.barValueMode, display: settings.barDisplayMode)
        if menuBarHiddenCount != n { menuBarHiddenCount = n }
    }

    /// Drops samples older than the configured retention window (and enforces the cap).
    private func trimHistory(now: Date) {
        let cutoff = now.addingTimeInterval(-Double(settings.historyRetentionMinutes) * 60)
        if let firstFresh = history.firstIndex(where: { $0.time >= cutoff }), firstFresh > 0 {
            history.removeFirst(firstFresh)
        }
        if history.count > historyHardCap {
            history.removeFirst(history.count - historyHardCap)
        }
    }

    // MARK: Settings

    func apply(_ new: AppSettings) {
        let old = settings
        settings = new
        Loc.language = new.language
        Self.saveSettings(new)
        if old.baseInterval != new.baseInterval { recomputeInterval() }
        if old.launchAtLogin != new.launchAtLogin { applyLaunchAtLogin(new.launchAtLogin) }
        if old.overviewOrder != new.overviewOrder || old.barMetrics != new.barMetrics {
            engine.setEnabledMetrics(neededMetricKinds())
        }
        if old.historyRetentionMinutes != new.historyRetentionMinutes {
            trimHistory(now: Date())
        }
        if old.barMetrics != new.barMetrics || old.barValueMode != new.barValueMode
            || old.barDisplayMode != new.barDisplayMode {
            recomputeMenuBarFit()
        }
    }

    /// Collectors required by the active sections and the menu-bar cells. Hidden
    /// metrics are excluded so the engine gathers no data for them.
    private func neededMetricKinds() -> Set<MetricKind> {
        var kinds: Set<MetricKind> = []
        for section in settings.overviewOrder {
            switch section {
            case .network: kinds.insert(.network)
            case .disk: kinds.insert(.disk)
            case .gpu: kinds.insert(.gpu)
            case .battery: kinds.insert(.battery)
            case .cpu, .memory: break
            }
        }
        for metric in settings.barMetrics {
            switch metric {
            case .network: kinds.insert(.network)
            case .disk: kinds.insert(.disk)
            case .gpu: kinds.insert(.gpu)
            case .battery: kinds.insert(.battery)
            case .cpu, .memory: break
            }
        }
        return kinds
    }

    /// A live binding to one setting. Mutations apply (and persist) immediately,
    /// so Settings needs no explicit Save step.
    func binding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { self.settings[keyPath: keyPath] },
            set: { newValue in
                var updated = self.settings
                updated[keyPath: keyPath] = newValue
                self.apply(updated)
            }
        )
    }

    // MARK: Popover lifecycle

    func popoverAppeared(tab: PopoverTab) {
        popoverVisible = true
        applyTab(tab)
        engine.refreshNow()
        recomputeInterval()
    }

    func popoverDisappeared() {
        popoverVisible = false
        engine.setIncludeSensors(false)
        engine.setIncludeProcesses(false)
        recomputeInterval()
    }

    func applyTab(_ tab: PopoverTab) {
        engine.setIncludeSensors(tab == .sensors)
        engine.setIncludeProcesses(tab == .overview)
        engine.refreshNow()
    }

    // MARK: Adaptive interval

    private func recomputeInterval() {
        var interval = settings.baseInterval
        let onBattery = !(snapshot.battery?.isPluggedIn ?? true)
        if ProcessInfo.processInfo.isLowPowerModeEnabled { interval *= 3 }
        if onBattery { interval *= 1.5 }
        if popoverVisible { interval = min(interval, 2) }
        engine.setInterval(max(1, interval))
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Log.error("Launch-at-login change failed: \(error.localizedDescription)")
        }
    }

    /// Reconciles the registered login item with the setting on launch, so the
    /// default-on behaviour takes effect without the user toggling it.
    private func syncLaunchAtLogin() {
        let status = SMAppService.mainApp.status
        if settings.launchAtLogin, status != .enabled {
            applyLaunchAtLogin(true)
        } else if !settings.launchAtLogin, status == .enabled {
            applyLaunchAtLogin(false)
        }
    }

    // MARK: Persistence

    /// One-line environment summary for the log header. The screen / notch details matter
    /// because macOS silently hides menu-bar items that don't fit beside a notch.
    private static func launchInfo() -> String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let screens = NSScreen.screens.enumerated().map { index, s -> String in
            let size = s.frame.size
            let notch = s.safeAreaInsets.top > 0 ? " notch" : ""
            return "#\(index) \(Int(size.width))×\(Int(size.height))@\(Int(s.backingScaleFactor))x\(notch)"
        }.joined(separator: ", ")
        return "v\(version) (\(build)), \(os), screens: [\(screens)]"
    }

    private static func loadSettings() -> AppSettings? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return nil }
        return try? JSONDecoder().decode(AppSettings.self, from: data)
    }

    private static func saveSettings(_ settings: AppSettings) {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}
