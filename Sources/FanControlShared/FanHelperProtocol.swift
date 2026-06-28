import Foundation

/// Shared contract between the main (user) app and the privileged fan-control helper.
/// Kept dependency-free so both the SwiftUI app and the root daemon can import it.

public enum FanHelper {
    /// Mach service the helper registers (must match the LaunchDaemon plist `MachServices` key).
    public static let machServiceName = "com.tinystats.fanhelper"
    /// Bumped when the wire protocol changes, so the app can detect a stale installed helper.
    public static let protocolVersion = 1
    /// Helper reverts every fan to auto if it gets no command/heartbeat within this window.
    /// The app heartbeats well inside it, so a crashed/hung/killed app fails safe to auto.
    public static let watchdogSeconds: TimeInterval = 6
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
