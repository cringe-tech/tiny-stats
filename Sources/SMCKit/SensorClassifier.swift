import Foundation

/// CPU architecture of the host, detected once at runtime. A universal binary can
/// run on either, so this is a runtime sysctl rather than a compile-time `#if`.
public enum MacArch: Sendable {
    case appleSilicon
    case intel

    public static let current: MacArch = {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("hw.optional.arm64", &value, &size, nil, 0) == 0, value == 1 {
            return .appleSilicon
        }
        return .intel
    }()
}

/// The logical component a temperature sensor belongs to.
public enum TempComponent: String, Sendable, CaseIterable {
    case cpu = "CPU"
    case memory = "Memory"
    case gpu = "GPU"
    case power = "Power"
}

/// Maps raw SMC temperature keys onto logical components. SMC keys differ between
/// Intel and Apple Silicon, so the prefix table is chosen per architecture. Matching
/// is case-sensitive on purpose: on Apple Silicon `Tp…` (CPU performance cores) and
/// `TP…` (power delivery) differ only by case.
public enum SensorClassifier {
    public static func component(forKey key: String, arch: MacArch = .current) -> TempComponent? {
        switch arch {
        case .appleSilicon:
            if key.hasPrefix("Tp") || key.hasPrefix("Te") || key.hasPrefix("TC") { return .cpu }
            if key.hasPrefix("Tg") { return .gpu }
            if key.hasPrefix("Tm") { return .memory }
            if key.hasPrefix("TP") { return .power }
        case .intel:
            if key.hasPrefix("TC") { return .cpu }
            if key.hasPrefix("TG") { return .gpu }
            if key.hasPrefix("TM") { return .memory }
            if key.hasPrefix("Tp") || key.hasPrefix("TP") { return .power }
        }
        return nil
    }
}
