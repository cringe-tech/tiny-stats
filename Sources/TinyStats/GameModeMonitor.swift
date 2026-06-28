import Foundation
import CGameMode   // notify_register_dispatch / notify_get_state (Darwin notifications)

/// Observes macOS Game Mode through its public Darwin notification, so Turbo can follow the exact
/// same state the system shows in the menu bar.
///
/// Reliable where the alternatives are not: macOS exposes no Game Mode API and its `gamepolicyd`
/// daemon is root-owned and lingers after a game quits; fullscreen games capture the display so
/// they never appear in the window list; and GPU "utilisation" idles high (the desktop compositor
/// keeps the renderer busy). But `gamepolicyd` posts `com.apple.system.game_mode_status_changed`,
/// a state-bearing notification (0 = off, non-zero = on) any process can register for — no root.
final class GameModeMonitor {
    /// macOS posts this when Game Mode turns on or off; its state value is 0/1.
    private static let notificationName = "com.apple.system.game_mode_status_changed"

    private var token: Int32 = -1
    private let onChange: @Sendable (Bool) -> Void

    /// `onChange` is called on the main queue with the current state at registration and on
    /// every subsequent change.
    init(onChange: @escaping @Sendable (Bool) -> Void) {
        self.onChange = onChange
        var registered: Int32 = 0
        let status = notify_register_dispatch(Self.notificationName, &registered, DispatchQueue.main) { tok in
            onChange(Self.readState(tok))
        }
        guard status == NOTIFY_STATUS_OK else { return }
        token = registered
        onChange(Self.readState(registered))   // seed with the current state
    }

    deinit {
        if token != -1 { notify_cancel(token) }
    }

    private static func readState(_ token: Int32) -> Bool {
        var state: UInt64 = 0
        guard notify_get_state(token, &state) == NOTIFY_STATUS_OK else { return false }
        return state != 0
    }
}
