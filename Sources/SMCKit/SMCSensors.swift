import Foundation

public enum SensorCategory: String, Sendable, CaseIterable {
    case temperature
    case fan
    case voltage
    case current
    case power
}

public struct SensorReading: Sendable, Identifiable, Hashable {
    public var id: String { key }
    public let key: String
    public let name: String
    public let category: SensorCategory
    public let value: Double
    public let unit: String
}

/// Discovers and reads the sensors exposed by the SMC. Read-only.
///
/// Apple changes sensor keys with every SoC and the FourCC codes are nearly arbitrary,
/// so rather than hardcoding a per-chip table we enumerate the keys once, categorise them
/// by prefix, and keep only readings that fall in a plausible physical range. This adapts
/// across chips without guessing wrong keys.
public final class SMCSensors {
    private let smc: SMCConnection
    private var tempKeys: [String] = []
    private var voltageKeys: [String] = []
    private var currentKeys: [String] = []
    private var powerKeys: [String] = []
    private var fanCount: Int = 0
    private var discovered = false

    public init?() {
        guard let smc = SMCConnection() else { return nil }
        self.smc = smc
    }

    /// Enumerating ~2000 SMC keys is not free, so we defer it until something actually
    /// needs sensors (i.e. the sensors view becomes visible) rather than at launch.
    private func discover() {
        guard !discovered else { return }
        discovered = true
        let keys = smc.allKeys()
        fanCount = Int(smc.read("FNum")?.double ?? 0)

        for key in keys {
            guard let first = key.first else { continue }
            switch first {
            case "T": tempKeys.append(key)
            case "V": voltageKeys.append(key)
            case "I": currentKeys.append(key)
            case "P": powerKeys.append(key)
            default: break
            }
        }
        // Prune keys that don't actually decode to a plausible value, so the lists
        // don't fill with control/meta keys that share a prefix.
        tempKeys = tempKeys.filter { plausible(smc.read($0)?.double, 1, 130) }
        voltageKeys = voltageKeys.filter { plausible(smc.read($0)?.double, 0.1, 30) }
        currentKeys = currentKeys.filter { plausible(smc.read($0)?.double, 0.01, 120) }
        powerKeys = powerKeys.filter { plausible(smc.read($0)?.double, 0.01, 400) }
    }

    private func plausible(_ value: Double?, _ low: Double, _ high: Double) -> Bool {
        guard let v = value, v.isFinite else { return false }
        return v >= low && v <= high
    }

    /// Reads the current value of every discovered sensor. Discovery happens lazily on
    /// the first call.
    public func readAll() -> [SensorReading] {
        discover()
        var out: [SensorReading] = []

        for key in tempKeys {
            if let v = smc.read(key)?.double, v.isFinite {
                out.append(.init(key: key, name: key, category: .temperature, value: v, unit: "°C"))
            }
        }
        for i in 0..<fanCount {
            if let v = smc.read("F\(i)Ac")?.double, v.isFinite {
                out.append(.init(key: "F\(i)Ac", name: "Fan \(i + 1)", category: .fan, value: v, unit: "RPM"))
            }
        }
        for key in voltageKeys {
            if let v = smc.read(key)?.double, v.isFinite {
                out.append(.init(key: key, name: key, category: .voltage, value: v, unit: "V"))
            }
        }
        for key in currentKeys {
            if let v = smc.read(key)?.double, v.isFinite {
                out.append(.init(key: key, name: key, category: .current, value: v, unit: "A"))
            }
        }
        for key in powerKeys {
            if let v = smc.read(key)?.double, v.isFinite {
                out.append(.init(key: key, name: key, category: .power, value: v, unit: "W"))
            }
        }
        return out
    }

    public var fans: Int { fanCount }
}
