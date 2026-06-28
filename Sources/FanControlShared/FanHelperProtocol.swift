import Foundation

/// Shared contract between the main (user) app and the privileged fan-control helper.
/// Kept dependency-free so both the SwiftUI app and the root daemon can import it.

public enum FanHelper {
    /// Mach service the helper registers (must match the LaunchDaemon plist `MachServices` key).
    public static let machServiceName = "com.cringetech.tinystats.fanhelper"
    /// Bumped when the wire protocol changes, so the app can detect a stale installed helper.
    public static let protocolVersion = 1
    /// Helper reverts every fan to auto if it gets no command/heartbeat within this window.
    /// The app heartbeats well inside it, so a crashed/hung/killed app fails safe to auto.
    public static let watchdogSeconds: TimeInterval = 6

    /// Code-signing requirement the helper enforces on every XPC peer
    /// (`NSXPCConnection.setCodeSigningRequirement`), so a random local process can't drive the
    /// root daemon. It pins the *packaged* app's signing identifier; under `swift run` the dev
    /// binary's identifier differs (and changes per build), so fan control must be exercised
    /// from the bundled `TinyStats.app`. With only ad-hoc signing this is best-effort (an
    /// attacker could ad-hoc-sign with the same identifier) — the helper-side clamp + watchdog
    /// remain the real safety boundary. Strengthen to an `anchor`/team-ID requirement once the
    /// app is Developer ID-signed.
    public static let clientCodeRequirement = "identifier \"com.cringetech.tinystats.app\""
}

/// One fan's live state, as reported by the helper (which owns the privileged SMC connection).
public struct FanInfo: Codable, Sendable, Identifiable, Equatable {
    public let index: Int
    public let minRPM: Double
    public let maxRPM: Double
    public let actualRPM: Double
    public let mode: Int            // 0 = auto (system), 1 = forced (helper-controlled)
    public var id: Int { index }

    public init(index: Int, minRPM: Double, maxRPM: Double, actualRPM: Double, mode: Int) {
        self.index = index
        self.minRPM = minRPM
        self.maxRPM = maxRPM
        self.actualRPM = actualRPM
        self.mode = mode
    }
}

/// Snapshot returned by `info` — helper version plus every fan's state.
public struct FanHelperInfo: Codable, Sendable {
    public let protocolVersion: Int
    public let fans: [FanInfo]

    public init(protocolVersion: Int, fans: [FanInfo]) {
        self.protocolVersion = protocolVersion
        self.fans = fans
    }
}

/// XPC interface the helper vends. The app is the client; the helper performs the SMC writes
/// as root. All hardware-safety rules (clamp to [min,max], watchdog revert-to-auto) live in
/// the helper, so even an untrusted caller can't drive the fans outside safe limits.
///
/// `info` replies with a JSON-encoded `FanHelperInfo` (`Data?`) rather than the struct directly,
/// to avoid NSSecureCoding ceremony over XPC; both sides share the Codable type.
@objc public protocol FanHelperProtocol {
    func info(reply: @escaping @Sendable (Data?) -> Void)
    func setTarget(fan index: Int, rpm: Double, reply: @escaping @Sendable (Bool) -> Void)
    func setAuto(fan index: Int, reply: @escaping @Sendable (Bool) -> Void)
    func setAutoAll(reply: @escaping @Sendable (Bool) -> Void)
    func heartbeat(reply: @escaping @Sendable (Bool) -> Void)
}
