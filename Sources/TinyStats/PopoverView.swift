import SwiftUI
import AppKit
import TinyStatsCore
import SMCKit

enum PopoverTab: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case history = "History"
    case sensors = "Sensors"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview: return Loc.t(.overview)
        case .history: return Loc.t(.history)
        case .sensors: return Loc.t(.sensors)
        }
    }
}

struct PopoverView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openWindow) private var openWindow
    @State private var tab: PopoverTab = .overview
    @State private var hoveredTab: PopoverTab?
    @State private var hostWindow: NSWindow?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            tabBar
                .padding(.bottom, 10)
            ScrollView {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, 2)
            }
            .scrollIndicators(.never)
            Divider()
                .padding(.vertical, 4)
            footer
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(width: 300, height: 440)
        .background(WindowAccessor { window in
            hostWindow = window
            DispatchQueue.main.async { window?.makeKey() }   // first time the panel is created
        })
        .onAppear {
            if !visibleTabs.contains(tab) { tab = .overview }
            state.popoverAppeared(tab: tab)
            // The .window-style MenuBarExtra popover is shown but not made key, so the first
            // click inside it is swallowed to focus the window instead of hitting the tapped
            // control. Make the panel key once it has finished presenting (the panel is
            // reused across opens, so the WindowAccessor callback above only fires the first
            // time — this re-asserts key on every reopen). We deliberately do NOT call
            // NSApp.activate here: for an LSUIElement agent that can pull focus away and make
            // the nonactivating panel resign key, which is the opposite of what we want.
            makeKeySoon()
        }
        .onDisappear { state.popoverDisappeared() }
        .onChange(of: tab) { _, newValue in
            state.applyTab(newValue)
        }
        .onChange(of: state.settings.showHistoryTab) { _, _ in
            if !visibleTabs.contains(tab) { tab = .overview }
        }
    }

    private var visibleTabs: [PopoverTab] {
        state.settings.showHistoryTab ? PopoverTab.allCases : [.overview, .sensors]
    }

    /// Make the popover panel key shortly after it appears — a tiny delay lets it finish
    /// presenting, otherwise `makeKey()` runs before the window is on screen and is ignored.
    private func makeKeySoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            hostWindow?.makeKey()
        }
    }

    // MARK: Tab bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(Array(visibleTabs.enumerated()), id: \.element) { index, t in
                Button { withAnimation(.easeInOut(duration: 0.15)) { tab = t } } label: {
                    VStack(spacing: 0) {
                        Text(t.title)
                            .font(.system(.callout, weight: tab == t ? .semibold : .regular))
                            .foregroundStyle(tab == t ? Color.primary : hoveredTab == t ? Color.primary : Color.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                        Rectangle()
                            .fill(tab == t ? Color.accentColor : hoveredTab == t ? Color.accentColor.opacity(0.3) : Color.clear)
                            .frame(height: 2)
                    }
                    // Make the whole cell tappable, not just the glyphs — the padding and the
                    // (clear, for unselected tabs) underline strip aren't hit-testable otherwise.
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                .onHover { hovered in hoveredTab = hovered ? t : nil }
            }
        }
        .background(alignment: .bottom) {
            Rectangle().fill(.separator).frame(height: 1)
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .overview:
            OverviewView(
                snapshot: state.snapshot,
                topCount: state.settings.topProcessCount,
                order: state.settings.overviewOrder,
                processListEnabled: state.settings.processListEnabled,
                showProcessesCPU: state.settings.showProcessesCPU,
                showProcessesMemory: state.settings.showProcessesMemory,
                showProcessesDisk: state.settings.showProcessesDisk,
                nerd: state.settings.nerdStats,
                lowPower: state.lowPowerMode
            )
        case .history:
            HistoryView(
                samples: state.history,
                order: state.settings.overviewOrder,
                snapshot: state.snapshot
            )
        case .sensors:
            SensorsView(sensors: state.snapshot.sensors,
                        nerd: state.settings.nerdStats,
                        temperatureUnit: state.settings.temperatureUnit)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            PopoverFooterButton(symbol: "gearshape", title: Loc.t(.settings)) {
                NSApplication.shared.activate(ignoringOtherApps: true)
                openWindow(id: SettingsWindow.id)
            }
            .keyboardShortcut(",", modifiers: .command)
            Spacer()
            PopoverFooterButton(symbol: "power", title: Loc.t(.quit), role: .destructive) {
                NSApplication.shared.terminate(nil)
            }
        }
        .font(.system(.callout))
    }
}

/// Hands back the hosting NSWindow once this view lands in one, so SwiftUI code (which has
/// no other way to reach it) can call AppKit APIs like `makeKey()` on it.
struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = CallbackView()
        view.onWindow = onWindow
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class CallbackView: NSView {
        var onWindow: ((NSWindow?) -> Void)?
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); onWindow?(window) }
    }
}

/// Footer button with hover highlight.
private struct PopoverFooterButton: View {
    let symbol: String
    let title: String
    var role: ButtonRole? = nil
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(role: role, action: action) {
            Label(title, systemImage: symbol)
                .foregroundStyle(foregroundColor)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }

    private var foregroundColor: Color {
        if role == .destructive { return hovered ? .red : .secondary }
        return hovered ? .primary : .secondary
    }
}
