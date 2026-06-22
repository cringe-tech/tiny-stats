import SwiftUI
import AppKit
import TinyStatsCore

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.colorScheme) private var colorScheme
    @State private var dock = DockPresence()

    private static let donationURL = URL(string:
        "https://nowpayments.io/donation?api_key=857516d3-5dfc-47f3-a1bb-1a4c01b3f4be")!
    private static let kofiURL = URL(string: "https://ko-fi.com/cringetech")!
    private static let makerURL = URL(string: "https://cringetech.org")!
    private static let repoURL = URL(string: "https://github.com/cringe-tech/tiny-stats")!
    private static let issuesURL = URL(string: "https://github.com/cringe-tech/tiny-stats/issues")!

    var body: some View {
        TabView {   
            generalTab
                .tabItem { Label(Loc.t(.general), systemImage: "gearshape") }
            menuBarTab
                .tabItem { Label(Loc.t(.menuBar), systemImage: "menubar.rectangle") }
            panelsTab
                .tabItem { Label(Loc.t(.panels), systemImage: "rectangle.3.group") }
        }
        .frame(width: 480, height: 740)
        // Rebuild on language change so every control (incl. cached Picker labels) re-localizes.
        .id(state.settings.language)
        // Give the window a Dock icon + cmd-tab presence while it's open (see DockPresence).
        .background(WindowAccessor { dock.attach(to: $0) })
    }

    // MARK: General tab

    private var generalTab: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Toggle(Loc.t(.launchAtLogin), isOn: state.binding(\.launchAtLogin))
                    if UpdateChecker.isConfigured {
                        Toggle(Loc.t(.autoCheckUpdates), isOn: state.binding(\.autoCheckUpdates))
                    }
                    Picker(Loc.t(.language), selection: state.binding(\.language)) {
                        ForEach(AppLanguage.allCases) { Text($0.displayName).tag($0) }
                    }
                }

                Section(Loc.t(.updates)) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 12) {
                            Text(Loc.t(.refreshInterval))
                            Slider(value: state.binding(\.baseInterval), in: 1...30, step: 1)
                                .onChange(of: state.settings.baseInterval) { _, _ in Haptic.tick() }
                            Text("\(state.settings.baseInterval, specifier: "%.0f")s")
                                .foregroundStyle(.secondary).monospacedDigit()
                        }
                        Text(Loc.t(.refreshHint))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section(Loc.t(.history)) {
                    Toggle(Loc.t(.showHistoryTab), isOn: state.binding(\.showHistoryTab))
                    Picker(Loc.t(.keepHistoryFor), selection: retentionBinding) {
                        ForEach(HistoryRetention.allCases) { Text($0.label).tag($0) }
                    }
                }

                Section(Loc.t(.sensors)) {
                    Picker(Loc.t(.temperatureUnit), selection: state.binding(\.temperatureUnit)) {
                        ForEach(TemperatureUnit.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Toggle(isOn: state.binding(\.nerdStats)) {
                        VStack(alignment: .leading) {
                            Text(Loc.t(.nerdStats))
                            Text(Loc.t(.nerdStatsHint))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                Section(Loc.t(.diagnostics)) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Button(Loc.t(.exportLogs)) { exportLogs() }
                            Button(Loc.t(.revealLogs)) { revealLogs() }
                        }
                        Text(Loc.t(.logsHint))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .hideScrollers()

            // About sits outside the Form so it has no grouped "card" backing behind it.
            aboutContent
                .padding(.horizontal, 20)
                .padding(.bottom, 10)
        }
        .background(FocusClearer())
    }

    // MARK: Menu Bar tab

    private var menuBarTab: some View {
        Form {
            Section(Loc.t(.preview)) {
                previewBar
                if state.menuBarHiddenCount > 0 {
                    Label(Loc.t(.cellsHidden, "\(state.menuBarHiddenCount)"), systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            Section(Loc.t(.menuBarCells)) {
                MenuBarArrangementView(metrics: state.binding(\.barMetrics))
            }
            Section(Loc.t(.defaultSet)) {
                HStack {
                    BarLabelView(snapshot: state.snapshot, metrics: defaultBarMetrics,
                                 mode: state.settings.barValueMode, display: .iconValue)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(Loc.t(.useDefault)) {
                        var s = state.settings
                        s.barMetrics = defaultBarMetrics
                        state.apply(s)
                    }
                    .disabled(state.settings.barMetrics == defaultBarMetrics)
                }
            }
            Section(Loc.t(.show)) {
                Picker(Loc.t(.cellsShow), selection: state.binding(\.barDisplayMode)) {
                    ForEach(BarDisplayMode.allCases) { Text($0.label).tag($0) }
                }
            }
        }
        .formStyle(.grouped)
        .hideScrollers()
    }

    // MARK: Panels tab

    private var panelsTab: some View {
        Form {
            Section(Loc.t(.metrics)) {
                Text(Loc.t(.metricsHint))
                    .font(.caption).foregroundStyle(.secondary)
                SectionsArrangementView()
            }
            Section(Loc.t(.processLists)) {
                Toggle(Loc.t(.showProcessLists), isOn: state.binding(\.processListEnabled))
                Group {
                    Stepper(value: state.binding(\.topProcessCount), in: 1...20) {
                        HStack {
                            Text(Loc.t(.topProcesses))
                            Spacer()
                            Text("\(state.settings.topProcessCount)").foregroundStyle(.secondary)
                        }
                    }
                    Toggle(Loc.t(.cpuSection), isOn: state.binding(\.showProcessesCPU))
                    Toggle(Loc.t(.memorySection), isOn: state.binding(\.showProcessesMemory))
                    Toggle(Loc.t(.diskSection), isOn: state.binding(\.showProcessesDisk))
                }
                .disabled(!state.settings.processListEnabled)
            }
        }
        .formStyle(.grouped)
        .hideScrollers()
    }

    // MARK: Pieces

    private let defaultBarMetrics: [BarMetric] = [.cpu, .memory, .network]

    private var retentionBinding: Binding<HistoryRetention> {
        Binding(
            get: { HistoryRetention(rawValue: state.settings.historyRetentionMinutes) ?? .m15 },
            set: { newValue in
                var s = state.settings
                s.historyRetentionMinutes = newValue.rawValue
                state.apply(s)
            }
        )
    }

    private var previewBar: some View {
        HStack {
            Spacer()
            BarLabelView(snapshot: state.snapshot,
                         metrics: state.settings.barMetrics,
                         mode: state.settings.barValueMode,
                         display: state.settings.barDisplayMode)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var aboutContent: some View {
        VStack(spacing: 14) {
            // Two equal columns: the left badge hugs the centre (trailing), the right one
            // hugs it too (leading). This keeps both buttons anchored either side of the
            // midline so they don't drift when localized labels change the panel width.
            HStack(alignment: .center, spacing: 12) {
                if let button = Self.kofiButton(for: colorScheme) {
                    DonateBadge(image: button, url: Self.kofiURL, help: "Ko-fi", secretHint: Loc.t(.switchTabs))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                CryptoDonateButton(url: Self.donationURL, help: Loc.t(.donate))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .zIndex(1)   // let the Ko-fi easter-egg pill float above the rows below
            VStack(alignment: .center, spacing: 2) {
                HStack(spacing: 5) {
                    HoverLink(title: "GitHub", url: Self.repoURL)
                    Text("·").font(.system(.caption2)).foregroundStyle(.tertiary)
                    HoverLink(title: Loc.t(.reportIssue), url: Self.issuesURL)
                }
                HStack(spacing: 3) {
                    Text("made by").font(.system(.caption2)).foregroundStyle(.secondary)
                    HoverLink(title: "cringe tech", url: Self.makerURL)
                }
                Text("TinyStats")
                    .font(.system(.body, weight: .semibold))
            }
            VStack(spacing: 4) {
                Text("\(Loc.t(.version)) \(appVersion) · Build \(appBuild)")
                    .font(.system(.subheadline))
                    .foregroundStyle(.secondary)
                updateRow
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    /// Update status / action, shown only once the release repo is configured.
    @ViewBuilder
    private var updateRow: some View {
        if UpdateChecker.isConfigured {
            switch state.updateStatus {
            case .checking:
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(Loc.t(.checkingUpdates)).font(.system(.subheadline)).foregroundStyle(.secondary)
                }
            case .upToDate:
                Text(Loc.t(.upToDate)).font(.system(.subheadline)).foregroundStyle(.secondary)
            case let .available(version, url):
                VStack(spacing: 4) {
                    Text(Loc.t(.updateAvailable, "v\(version)"))
                        .font(.system(.subheadline, weight: .medium))
                    // Homebrew-managed copies update through brew, not the raw .dmg, so an
                    // overwriting drag-install doesn't fight the cask's bookkeeping.
                    if UpdateChecker.installedViaHomebrew {
                        Button(Loc.t(.updateViaHomebrew)) { state.updateViaHomebrew() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                    } else {
                        Link(Loc.t(.downloadUpdate), destination: url)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                    }
                }
            case .idle, .failed:
                VStack(spacing: 2) {
                    Button(Loc.t(.checkForUpdates)) { state.checkForUpdates(force: true) }
                        .controlSize(.small)
                    if state.updateStatus == .failed {
                        Text(Loc.t(.updateFailed)).font(.system(.caption2)).foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    /// Loads a bundled PNG. In the packaged .app the images sit in Contents/Resources, so
    /// `Bundle.main` finds them and we never touch `Bundle.module` — whose generated accessor
    /// fatalErrors when the SwiftPM bundle isn't where it expects. The `Bundle.module` fallback
    /// only runs under `swift run`, where it resolves against the build directory.
    private static func resourceImage(_ name: String) -> NSImage? {
        let url = Bundle.main.url(forResource: name, withExtension: "png")
            ?? Bundle.module.url(forResource: name, withExtension: "png")
        return url.flatMap(NSImage.init(contentsOf:))
    }

    private static func nowPaymentsButton(for scheme: ColorScheme) -> NSImage? {
        // Match the theme: dark button in dark mode, light button in light mode.
        resourceImage(scheme == .dark ? "nowpayments-black" : "nowpayments-white")
    }

    private static func kofiButton(for scheme: ColorScheme) -> NSImage? {
        resourceImage(scheme == .dark ? "kofi-dark" : "kofi-beige")
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var appBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    /// Writes the combined log (previous + current) to a user-chosen file for sharing.
    private func exportLogs() {
        let panel = NSSavePanel()
        let stamp = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none)
        panel.nameFieldStringValue = "tinystats-logs-\(stamp.replacingOccurrences(of: "/", with: "-")).log"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? Log.combinedText().write(to: url, atomically: true, encoding: .utf8)
    }

    private func revealLogs() {
        NSWorkspace.shared.activateFileViewerSelecting([Log.fileURL])
    }

    private static let logo: NSImage? = resourceImage("tinystats")
}

/// Gives the Settings window a Dock icon + cmd-tab presence while it's open, then removes it
/// on close. The app runs as an `LSUIElement` agent (`.accessory`, no Dock icon, invisible to
/// cmd-tab); switching to `.regular` while the window is up makes it findable again, and
/// reverting to `.accessory` on close restores the pure menu-bar mode.
@MainActor
private final class DockPresence {
    private var closeObserver: NSObjectProtocol?

    func attach(to window: NSWindow?) {
        guard let window else { return }   // ignore the detach (window == nil) callback
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        // Re-bind to the current window each open (the scene may recreate it), so close always
        // drops us back to .accessory.
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
            MainActor.assumeIsolated { _ = NSApp.setActivationPolicy(.accessory) }
        }
    }
}

/// Drop-zone chrome that is invisible at rest, shows a dashed border while a drag is
/// in progress, and highlights with the accent colour when the item hovers over it.
private struct DropZoneStyle: ViewModifier {
    let active: Bool
    let targeted: Bool

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(targeted ? Color.accentColor.opacity(0.15)
                          : active ? Color.gray.opacity(0.08) : Color.clear))
            .overlay {
                if active {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(targeted ? AnyShapeStyle(Color.accentColor)
                                              : AnyShapeStyle(Color.gray.opacity(0.35)),
                                      style: StrokeStyle(lineWidth: targeted ? 1.5 : 1,
                                                         dash: targeted ? [] : [4, 3]))
                }
            }
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.12), value: targeted)
            .animation(.easeOut(duration: 0.12), value: active)
    }
}

// MARK: - Menu bar cells (Mail-style "drag into toolbar" palette)

private struct MenuBarArrangementView: View {
    private enum ZoneID: String { case inBar, available }

    @Binding var metrics: [BarMetric]
    @State private var dragging: BarMetric?
    @State private var dragPoint: CGPoint = .zero
    @State private var targetZone: ZoneID?
    @State private var targetIndex = 0
    @State private var frames: [String: CGRect] = [:]
    @State private var hovered: BarMetric?
    @State private var limitBumped = false

    private let space = "menubar.reorder"
    private let tileRow: CGFloat = 70

    private var available: [BarMetric] { BarMetric.allCases.filter { !metrics.contains($0) } }

    private func zoneFrame(_ z: ZoneID) -> CGRect { frames["zone:\(z.rawValue)"] ?? .zero }
    private func zone(at point: CGPoint) -> ZoneID {
        if zoneFrame(.available).contains(point) { return .available }
        if zoneFrame(.inBar).contains(point) { return .inBar }
        return point.y > zoneFrame(.inBar).maxY ? .available : .inBar
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            zoneLabel(Loc.t(.inMenuBar))
            zoneView(.inBar, items: metrics)
            zoneLabel(Loc.t(.available))
            zoneView(.available, items: available)

            Text(Loc.t(.cellsHint))
                .font(.system(.caption2))
                .foregroundStyle(limitBumped ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.tertiary))
                .scaleEffect(limitBumped ? 1.06 : 1)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 1)
                .animation(.spring(response: 0.3, dampingFraction: 0.5), value: limitBumped)
        }
        .coordinateSpace(name: space)
        .onPreferenceChange(ReorderFrames.self) { frames = $0 }
        .overlay(alignment: .topLeading) { insertionIndicator }
        .overlay(alignment: .topLeading) { floating }
    }

    @ViewBuilder
    private func zoneView(_ z: ZoneID, items: [BarMetric]) -> some View {
        let targeted = targetZone == z
        ZStack {
            if items.isEmpty {
                Text(emptyHint(z, targeted: targeted))
                    .font(.caption)
                    .foregroundStyle(targeted ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
                    .padding(.vertical, 10)
            } else {
                FlowLayout(spacing: 10, lineSpacing: 10) {
                    ForEach(items) { metric in
                        tile(metric, inBar: z == .inBar, hovered: hovered == metric && dragging == nil)
                            .opacity(dragging == metric ? 0 : 1)
                            .reorderFrame(metric.rawValue, in: space)
                            .onHover { inside in
                                let was = hovered == metric
                                hovered = inside ? metric : (was ? nil : hovered)
                                if inside && !was && dragging == nil { Haptic.tick() }
                            }
                            .onTapGesture {
                                if z == .inBar {
                                    remove(metric.rawValue)
                                } else if !append(metric.rawValue), metrics.count >= 5 {
                                    bumpLimit()
                                }
                            }
                            .gesture(dragGesture(metric))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 56)
        .padding(8)
        .reorderFrame("zone:\(z.rawValue)", in: space)
        .modifier(DropZoneStyle(active: dragging != nil, targeted: targeted))
    }

    private func emptyHint(_ z: ZoneID, targeted: Bool) -> String {
        if z == .inBar { return dragging != nil ? Loc.t(.dropToAdd) : Loc.t(.tapToAdd) }
        return Loc.t(.removeHint)
    }

    @ViewBuilder
    private var floating: some View {
        if let dragging {
            tile(dragging, inBar: targetZone != .available)
                .scaleEffect(1.06)
                .shadow(color: .black.opacity(0.22), radius: 8, y: 4)
                .position(dragPoint)
                .allowsHitTesting(false)
        }
    }

    /// Accent line marking where the tile will land in the menu bar.
    @ViewBuilder
    private var insertionIndicator: some View {
        if dragging != nil, targetZone == .inBar {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.accentColor)
                .frame(width: 3, height: 44)
                .position(indicatorPoint(targetIndex))
                .allowsHitTesting(false)
        }
    }

    // MARK: Gesture (model is committed only on release, so the dragged tile never
    // moves mid-drag and the gesture can't be cancelled out from under itself)

    private func dragGesture(_ metric: BarMetric) -> some Gesture {
        LongPressGesture(minimumDuration: 0.16)
            .sequenced(before: DragGesture(coordinateSpace: .named(space)))
            .onChanged { value in
                guard case .second(true, let drag) = value else { return }
                if dragging == nil {
                    dragging = metric
                    if let f = frames[metric.rawValue] { dragPoint = CGPoint(x: f.midX, y: f.midY) }
                }
                if let drag {
                    dragPoint = drag.location
                    updateTarget(to: drag.location)
                }
            }
            .onEnded { _ in endReorder() }
    }

    /// Track the prospective drop (zone + insertion index) without touching the model.
    private func updateTarget(to point: CGPoint) {
        guard let dragged = dragging else { return }
        if zone(at: point) == .available {
            targetZone = .available
            targetIndex = 0
        } else {
            targetZone = .inBar
            targetIndex = flowIndex(point, items: metrics.filter { $0 != dragged })
        }
    }

    /// Glide the floating tile to its slot, then commit the move and clear the drag.
    private func endReorder() {
        guard let dragged = dragging, let tz = targetZone else { reset(); return }
        let index = targetIndex
        withAnimation(.snappy(duration: 0.18)) { dragPoint = dropAnchor(tz, index) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            commit(dragged, to: tz, at: index)
            reset()
        }
    }

    private func reset() { dragging = nil; targetZone = nil }

    private func commit(_ metric: BarMetric, to z: ZoneID, at index: Int) {
        var new = metrics.filter { $0 != metric }
        if z == .available {
            guard metrics.contains(metric), metrics.count > 1 else { return }   // keep at least one
        } else {
            guard metrics.contains(metric) || new.count < 5 else { return }     // up to 5
            new.insert(metric, at: max(0, min(index, new.count)))
        }
        guard new != metrics else { return }
        withAnimation(.snappy(duration: 0.2)) { metrics = new }
    }

    /// Insertion index in a wrapping row of tiles, by reading order.
    private func flowIndex(_ point: CGPoint, items: [BarMetric]) -> Int {
        var idx = 0
        for item in items {
            guard let f = frames[item.rawValue] else { continue }
            let before = f.midY < point.y - tileRow / 2
                || (abs(f.midY - point.y) <= tileRow / 2 && f.midX < point.x)
            if before { idx += 1 }
        }
        return idx
    }

    /// Point for the insertion line: left edge of the tile at `index` (or past the last).
    private func indicatorPoint(_ index: Int) -> CGPoint {
        let others = metrics.filter { $0 != dragging }
        let zf = zoneFrame(.inBar)
        guard !others.isEmpty else { return CGPoint(x: zf.midX, y: zf.midY) }
        if index >= others.count, let last = frames[others[others.count - 1].rawValue] {
            return CGPoint(x: last.maxX + 5, y: last.midY)
        }
        let i = max(0, min(index, others.count - 1))
        if let f = frames[others[i].rawValue] {
            return CGPoint(x: (index <= 0 ? f.minX : f.minX) - 5, y: f.midY)
        }
        return CGPoint(x: zf.midX, y: zf.midY)
    }

    /// Approximate centre where the dragged tile will settle (for the release glide).
    private func dropAnchor(_ z: ZoneID, _ index: Int) -> CGPoint {
        if z == .available { let zf = zoneFrame(.available); return CGPoint(x: zf.midX, y: zf.midY) }
        let others = metrics.filter { $0 != dragging }
        let zf = zoneFrame(.inBar)
        guard !others.isEmpty else { return CGPoint(x: zf.midX, y: zf.midY) }
        if index >= others.count, let last = frames[others[others.count - 1].rawValue] {
            return CGPoint(x: last.maxX + 5 + last.width / 2, y: last.midY)
        }
        let i = max(0, min(index, others.count - 1))
        if let f = frames[others[i].rawValue] { return CGPoint(x: f.midX, y: f.midY) }
        return CGPoint(x: zf.midX, y: zf.midY)
    }

    private func zoneLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(.caption2, weight: .semibold))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tile(_ metric: BarMetric, inBar: Bool, hovered: Bool = false) -> some View {
        // On hover the tile lights up in its own accent colour (even the muted "available"
        // ones) and grows slightly, so it's clear what you're about to grab.
        let iconColor: AnyShapeStyle = (inBar || hovered) ? AnyShapeStyle(metric.tint) : AnyShapeStyle(.secondary)
        let bgColor = hovered ? metric.tint.opacity(0.30)
            : inBar ? metric.tint.opacity(0.18) : Color.gray.opacity(0.12)
        return VStack(spacing: 5) {
            Image(systemName: metric.symbol)
                .font(.system(size: 17))
                .foregroundStyle(iconColor)
                .frame(width: 60, height: 36)
                .background(RoundedRectangle(cornerRadius: 8).fill(bgColor))
            Text(metric.label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .fixedSize()
        .contentShape(Rectangle())
        .scaleEffect(hovered ? 1.06 : 1)
        .animation(.easeOut(duration: 0.12), value: hovered)
    }

    /// Feedback when the user taps to add a cell but the 5-cell limit is reached: a haptic
    /// "no" plus a brief pulse of the "up to 5" hint, so the tap doesn't just silently fail.
    private func bumpLimit() {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        limitBumped = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { limitBumped = false }
    }

    // MARK: Mutations (single assignment so the binding stays reactive)

    @discardableResult
    private func append(_ raw: String?) -> Bool {
        guard let raw, let metric = BarMetric(rawValue: raw) else { return false }
        guard !metrics.contains(metric), metrics.count < 5 else { return false }
        withAnimation(.snappy) { metrics.append(metric) }
        return true
    }

    @discardableResult
    private func remove(_ raw: String?) -> Bool {
        guard let raw, let metric = BarMetric(rawValue: raw) else { return false }
        guard metrics.count > 1 else { return false }   // keep at least one cell
        withAnimation(.snappy) { metrics = metrics.filter { $0 != metric } }
        return true
    }
}

// MARK: - Custom reorder support (long-press drag with a floating item)

/// Captures item/zone frames in a named coordinate space so the drag can hit-test
/// insertion points and float the dragged item under the cursor.
struct ReorderFrames: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    func reorderFrame(_ id: String, in space: String) -> some View {
        background(GeometryReader { geo in
            Color.clear.preference(key: ReorderFrames.self, value: [id: geo.frame(in: .named(space))])
        })
    }
}

private struct SectionsArrangementView: View {
    private enum ZoneID: String { case active, hidden }

    @EnvironmentObject var state: AppState
    @State private var dragging: OverviewSection?
    @State private var dragPoint: CGPoint = .zero
    @State private var targetZone: ZoneID?
    @State private var targetIndex = 0
    @State private var frames: [String: CGRect] = [:]
    @State private var hoveredSection: OverviewSection?

    private let space = "panels.reorder"
    private let rowHeight: CGFloat = 28

    private var active: [OverviewSection] { state.settings.overviewOrder }
    private var inactive: [OverviewSection] { state.settings.inactiveSections }

    private func zoneFrame(_ z: ZoneID) -> CGRect { frames["zone:\(z.rawValue)"] ?? .zero }
    private func zone(at point: CGPoint) -> ZoneID {
        if zoneFrame(.hidden).contains(point) { return .hidden }
        if zoneFrame(.active).contains(point) { return .active }
        return point.y > zoneFrame(.active).maxY ? .hidden : .active
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            label(Loc.t(.active))
            zoneView(.active, items: active)
            label(Loc.t(.hiddenNotCollected))
            zoneView(.hidden, items: inactive)
        }
        .coordinateSpace(name: space)
        .onPreferenceChange(ReorderFrames.self) { frames = $0 }
        .overlay(alignment: .topLeading) { insertionIndicator }
        .overlay(alignment: .topLeading) { floating }
    }

    @ViewBuilder
    private func zoneView(_ z: ZoneID, items: [OverviewSection]) -> some View {
        let targeted = targetZone == z
        VStack(spacing: 6) {
            if items.isEmpty {
                Text(dragging != nil ? Loc.t(.dropToHide) : Loc.t(.dragToHide))
                    .font(.caption)
                    .foregroundStyle(targeted ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
                    .frame(maxWidth: .infinity, minHeight: dragging != nil ? 40 : 22)
            } else {
                ForEach(items) { section in
                    row(section, hidden: z == .hidden, hovered: hoveredSection == section && dragging == nil)
                        .opacity(dragging == section ? 0 : 1)
                        .reorderFrame(section.rawValue, in: space)
                        .onHover { inside in
                            let was = hoveredSection == section
                            hoveredSection = inside ? section : (was ? nil : hoveredSection)
                            if inside && !was && dragging == nil { Haptic.tick() }
                        }
                        .onTapGesture { toggleZone(section, from: z) }
                        .gesture(dragGesture(section))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .reorderFrame("zone:\(z.rawValue)", in: space)
        .modifier(DropZoneStyle(active: dragging != nil, targeted: targeted))
    }

    /// The lifted item that floats under the cursor while dragging.
    @ViewBuilder
    private var floating: some View {
        if let dragging {
            let zf = zoneFrame(targetZone ?? .active)
            row(dragging, hidden: targetZone == .hidden)
                .frame(width: max(40, zf.width - 16))
                .scaleEffect(1.03)
                .shadow(color: .black.opacity(0.22), radius: 8, y: 4)
                .position(x: zf.midX, y: dragPoint.y)
                .allowsHitTesting(false)
        }
    }

    /// Accent line marking where the row will land.
    @ViewBuilder
    private var insertionIndicator: some View {
        if dragging != nil, let z = targetZone {
            let zf = zoneFrame(z)
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color.accentColor)
                .frame(width: max(40, zf.width - 16), height: 3)
                .position(x: zf.midX, y: indicatorY(z, targetIndex))
                .allowsHitTesting(false)
        }
    }

    // MARK: Gesture (model committed only on release → dragged row stays put → the
    // long-press/drag sequence is never cancelled by a mid-drag relayout)

    private func dragGesture(_ section: OverviewSection) -> some Gesture {
        LongPressGesture(minimumDuration: 0.16)
            .sequenced(before: DragGesture(coordinateSpace: .named(space)))
            .onChanged { value in
                guard case .second(true, let drag) = value else { return }
                if dragging == nil {
                    dragging = section
                    if let f = frames[section.rawValue] { dragPoint = CGPoint(x: f.midX, y: f.midY) }
                }
                if let drag {
                    dragPoint = drag.location
                    updateTarget(to: drag.location)
                }
            }
            .onEnded { _ in endReorder() }
    }

    /// Track the prospective drop (zone + insertion index) without touching the model.
    private func updateTarget(to point: CGPoint) {
        guard let dragged = dragging else { return }
        var z = zone(at: point)
        // Never hide the last remaining active metric.
        if z == .hidden && active.filter({ $0 != dragged }).isEmpty { z = .active }
        let others = (z == .active ? active : inactive).filter { $0 != dragged }
        targetZone = z
        targetIndex = others.filter { (frames[$0.rawValue]?.midY ?? 0) < point.y }.count
    }

    /// Glide the floating row to its slot, then commit the move and clear the drag.
    private func endReorder() {
        guard let dragged = dragging, let tz = targetZone else { reset(); return }
        let index = targetIndex
        withAnimation(.snappy(duration: 0.18)) { dragPoint.y = indicatorY(tz, index) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            commit(dragged, to: tz, at: index)
            reset()
        }
    }

    private func reset() { dragging = nil; targetZone = nil }

    /// Click to send a metric to the opposite zone (append to the end there).
    private func toggleZone(_ section: OverviewSection, from z: ZoneID) {
        if z == .active { commit(section, to: .hidden, at: inactive.count) }
        else { commit(section, to: .active, at: active.count) }
    }

    private func commit(_ section: OverviewSection, to z: ZoneID, at index: Int) {
        var newActive = active.filter { $0 != section }
        var newInactive = inactive.filter { $0 != section }
        if z == .hidden {
            if newActive.isEmpty { return }   // keep at least one active metric
            newInactive.insert(section, at: max(0, min(index, newInactive.count)))
        } else {
            newActive.insert(section, at: max(0, min(index, newActive.count)))
        }
        guard newActive != active || newInactive != inactive else { return }
        var s = state.settings
        s.overviewOrder = newActive
        s.inactiveSections = newInactive
        withAnimation(.snappy(duration: 0.2)) { state.apply(s) }
    }

    /// Y of the insertion line: between rows at `index`, or just past the ends.
    private func indicatorY(_ z: ZoneID, _ index: Int) -> CGFloat {
        let zf = zoneFrame(z)
        let rows = (z == .active ? active : inactive)
            .filter { $0 != dragging }
            .compactMap { frames[$0.rawValue] }
            .sorted { $0.midY < $1.midY }
        guard !rows.isEmpty else { return zf.midY }
        if index <= 0 { return rows[0].minY - 3 }
        if index >= rows.count { return rows[rows.count - 1].maxY + 3 }
        return (rows[index - 1].maxY + rows[index].minY) / 2
    }

    private func label(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(.caption2, weight: .semibold))
            .foregroundStyle(.tertiary)
    }

    private func row(_ section: OverviewSection, hidden: Bool, hovered: Bool = false) -> some View {
        // On hover the row picks up its section's accent colour and grows a touch.
        let iconColor: AnyShapeStyle = (hidden && !hovered) ? AnyShapeStyle(.tertiary) : AnyShapeStyle(section.tint)
        let background: AnyShapeStyle = hovered
            ? AnyShapeStyle(section.tint.opacity(0.18))
            : AnyShapeStyle(.quaternary.opacity(hidden ? 0.25 : 0.5))
        return HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 12)).foregroundStyle(.tertiary)
            Image(systemName: section.symbol)
                .font(.system(size: 11))
                .foregroundStyle(iconColor)
                .frame(width: 16)
            Text(section.label)
                .font(.system(size: 12))
                .foregroundStyle(hovered ? .primary : hidden ? .secondary : .primary)
            Spacer()
        }
        .padding(.horizontal, 8)
        .frame(height: rowHeight)
        .background(background, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .scaleEffect(hovered ? 1.025 : 1)
        .animation(.easeOut(duration: 0.12), value: hovered)
    }
}

/// Light haptic tick (the same subtle feedback AppKit uses for alignment-guide snaps),
/// played on trackpads that support Force Touch.
private enum Haptic {
    static func tick() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .drawCompleted)
    }
}

private extension View {
    /// Overlays a single AppKit layer that drives hover, the pointing-hand cursor, and clicks.
    ///
    /// Hover and cursor can't live on separate layers: an overlay that wins `cursorUpdate` (so
    /// the hand sticks despite the host re-setting the arrow on every mouse-move) also covers the
    /// content, so a SwiftUI `.onHover`/`.onTapGesture` underneath never fires; making the overlay
    /// hit-transparent in turn stops the system delivering it `cursorUpdate`. So this one view owns
    /// all three: `mouseEntered/Exited` → `hovered`, `cursorUpdate` → hand, `mouseUp` → `onClick`.
    func handInteraction(hovered: Binding<Bool>, onClick: @escaping () -> Void) -> some View {
        overlay(HandInteractionView(hovered: hovered, onClick: onClick))
    }
}

private struct HandInteractionView: NSViewRepresentable {
    @Binding var hovered: Bool
    let onClick: () -> Void

    func makeNSView(context: Context) -> NSView { V() }
    func updateNSView(_ v: NSView, context: Context) {
        guard let v = v as? V else { return }
        v.onHoverChange = { hovered = $0 }
        v.onClick = onClick
    }
    final class V: NSView {
        var onHoverChange: ((Bool) -> Void)?
        var onClick: (() -> Void)?
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: .zero,
                options: [.activeAlways, .cursorUpdate, .mouseEnteredAndExited, .inVisibleRect],
                owner: self))
        }
        override func cursorUpdate(with event: NSEvent) { NSCursor.pointingHand.set() }
        override func mouseEntered(with event: NSEvent) { onHoverChange?(true) }
        override func mouseExited(with event: NSEvent) { onHoverChange?(false) }
        override func mouseDown(with event: NSEvent) {}
        override func mouseUp(with event: NSEvent) {
            if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
        }
    }
}

/// A text link that brightens, underlines, and shows a hand cursor on hover.
private struct HoverLink: View {
    let title: String
    let url: URL
    @State private var hovering = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        Text(title)
            .font(.system(.caption2))
            .foregroundStyle(hovering ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
            .underline(hovering, pattern: .solid)
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.12), value: hovering)
            .handInteraction(hovered: $hovering) { openURL(url) }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(title)
            .accessibilityAddTraits(.isLink)
            .accessibilityAction { openURL(url) }
    }
}

/// A donation badge sized into a uniform slot (so the two buttons, which have different native
/// Text counterpart to the Ko-fi image badge: a bordered "Support with crypto" pill sized to
/// match `DonateBadge` (168×40) so the two donate columns stay visually balanced.
private struct CryptoDonateButton: View {
    let url: URL
    let help: String
    @State private var hovering = false
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme

    // Ko-fi's beige pill / dark border, mirrored so the crypto button reads as its twin.
    private var fill: Color {
        colorScheme == .dark ? Color(red: 0.16, green: 0.16, blue: 0.17)
                             : Color(red: 0.97, green: 0.94, blue: 0.88)
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "bitcoinsign.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.orange)
            Text("Support w/ crypto")
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 13)
        // Inner pill matches the Ko-fi image's rendered height (≈34), centred inside the same
        // 168×40 column box so both donate buttons line up.
        .frame(height: 34)
        .background(fill, in: Self.shape)
        .overlay(Self.shape.strokeBorder(.primary.opacity(0.85), lineWidth: 1.5))
        .frame(width: 168, height: 40)
        // Scale/shadow on hover, mirroring DonateBadge's lift.
        .scaleEffect(hovering ? 1.04 : 1)
        .shadow(color: .black.opacity(hovering ? 0.2 : 0), radius: hovering ? 6 : 0, y: 2)
        .animation(.easeOut(duration: 0.12), value: hovering)
        .contentShape(Self.shape)
        .handInteraction(hovered: $hovering) { openURL(url) }
        .help(help)
        .accessibilityLabel(help)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { openURL(url) }
    }

    // Rounded-rect (not a full capsule) to match the Ko-fi badge's corner radius.
    private static let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
}

/// aspect ratios, read as a tidy equal-width pair) that lifts on hover.
private struct DonateBadge: View {
    let image: NSImage
    let url: URL
    let help: String
    /// Optional easter egg: a little keyboard-shortcut hint that peeks out from under the
    /// button's bottom-right corner on hover.
    var secretHint: String? = nil
    @State private var hovering = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            if let secretHint {
                secretPill(secretHint)
                    // The pill drops out from under the badge's bottom-left (Ko-fi now sits in
                    // the left column, so it peeks toward the panel edge, away from the crypto
                    // button); the keycaps inside then pop in one-by-one for the playful reveal.
                    .offset(x: hovering ? -36 : -20, y: hovering ? 46 : 28)
                    .opacity(hovering ? 1 : 0)
                    .animation(.easeOut(duration: 0.18), value: hovering)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: 34)
                // Scale/shadow only the image, *inside* the stable 168×40 box below — if the
                // outer (hover-tracked) frame animated, its geometry would shift under the
                // cursor mid-grow and make onContinuousHover flicker the cursor.
                .scaleEffect(hovering ? 1.04 : 1)
                .shadow(color: .black.opacity(hovering ? 0.2 : 0), radius: hovering ? 6 : 0, y: 2)
                .animation(.easeOut(duration: 0.12), value: hovering)
                .frame(width: 168, height: 40)
                .contentShape(Rectangle())
                .handInteraction(hovered: $hovering) { openURL(url) }
                // Suppress the tooltip on the easter-egg badge so it doesn't pop over the pill.
                .help(secretHint == nil ? help : "")
                .accessibilityLabel(help)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { openURL(url) }
        }
    }

    private static let keyColors: [Color] = [.orange, .pink, .purple]
    private static let keyTilt: [Double] = [-6, 5, -4]

    private func secretPill(_ text: String) -> some View {
        // Two rows — caption on top, keycaps below — so the pill stays narrow and doesn't
        // spill past the panel edge regardless of how long the localized hint text is.
        VStack(spacing: 5) {
            Text(text)
                .font(.system(.caption2, design: .rounded).weight(.semibold))
                .foregroundStyle(.secondary)
                .opacity(hovering ? 1 : 0)
                .animation(.easeOut(duration: 0.2).delay(0.3), value: hovering)
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    Text("⌘\(i + 1)")
                        .font(.system(.caption2, design: .rounded).weight(.heavy))
                        .foregroundStyle(Self.keyColors[i])
                        .padding(.horizontal, 5).padding(.vertical, 3)
                        .background(Self.keyColors[i].opacity(0.18),
                                    in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .rotationEffect(.degrees(Self.keyTilt[i]))
                        // Each key pops in a beat after the previous one.
                        .scaleEffect(hovering ? 1 : 0.2, anchor: .bottom)
                        .opacity(hovering ? 1 : 0)
                        .offset(y: hovering ? 0 : 8)
                        .animation(.spring(response: 0.3, dampingFraction: 0.55)
                            .delay(Double(i) * 0.09), value: hovering)
                }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
            .strokeBorder(.quaternary, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.16), radius: 7, y: 3)
        .rotationEffect(.degrees(3))   // slightly hand-placed, indie feel — leans right
        .fixedSize()
    }
}

// MARK: - Overlay scrollers (the system "always show scroll bars" setting overrides
// SwiftUI's .scrollIndicators, so force the AppKit overlay style — it auto-hides at
// rest and only fades in, with native animation, while actively scrolling).

private extension View {
    func hideScrollers() -> some View { background(ScrollerHider()) }
}

private struct ScrollerHider: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { configure(from: view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { configure(from: nsView) }
    }

    private func configure(from view: NSView) {
        var node: NSView? = view.superview
        while let current = node {
            if let scrollView = current as? NSScrollView {
                scrollView.scrollerStyle = .overlay
                scrollView.autohidesScrollers = true
                scrollView.verticalScroller?.controlSize = .mini
                return
            }
            node = current.superview
        }
    }
}

// MARK: - Focus clearer (don't auto-focus a control when settings opens)

/// Clears the window's first responder on appear so opening Settings doesn't leave a
/// control (e.g. the Refresh interval slider) highlighted with a focus ring.
private struct FocusClearer: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            view.window?.initialFirstResponder = nil
            view.window?.makeFirstResponder(nil)
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// A wrapping layout that centres each row horizontally.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = rows(maxWidth: maxWidth, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +)
            + lineSpacing * CGFloat(max(0, rows.count - 1))
        let width = maxWidth.isFinite ? maxWidth : (rows.map(\.width).max() ?? 0)
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let rows = rows(maxWidth: bounds.width, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX + max(0, (bounds.width - row.width) / 2)
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(item.size))
                x += item.size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var items: [(index: Int, size: CGSize)] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let projected = current.items.isEmpty ? size.width : current.width + spacing + size.width
            if !current.items.isEmpty && projected > maxWidth {
                rows.append(current)
                current = Row()
            }
            current.width = current.items.isEmpty ? size.width : current.width + spacing + size.width
            current.items.append((index, size))
            current.height = max(current.height, size.height)
        }
        if !current.items.isEmpty { rows.append(current) }
        return rows
    }
}
