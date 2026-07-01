import SwiftUI

@main
struct TinyStatsApp: App {
    @State private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environment(state)
        } label: {
            MenuBarLabel(snapshot: state.snapshot,
                         metrics: state.settings.barMetrics,
                         mode: state.settings.barValueMode,
                         display: state.settings.barDisplayMode,
                         hiddenCount: state.menuBarHiddenCount,
                         lowPower: state.lowPowerMode,
                         menuBarIsDark: state.menuBarIsDark)
        }
        .menuBarExtraStyle(.window)

        Window("tiny-stats Settings", id: SettingsWindow.id) {
            SettingsView()
                .environment(state)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

enum SettingsWindow {
    static let id = "settings"
}
