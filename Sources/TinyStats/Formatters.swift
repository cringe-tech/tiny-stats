import Foundation

enum Format {
    static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    static func bytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .file)
    }

    /// Memory sizes in 1024-based units (still labelled "GB", as macOS's About This Mac does),
    /// so a 16 GiB machine reads "16 GB" rather than the decimal "17.18 GB" `.file` would give.
    static func memoryBytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .memory)
    }

    static func rate(_ bytesPerSec: Double) -> String {
        let v = max(0, bytesPerSec)
        if v < 1 { return "0 KB/s" }   // ByteCountFormatter renders 0 as "Zero KB"
        let formatted = ByteCountFormatter.string(fromByteCount: Int64(v), countStyle: .file)
        return "\(formatted)/s"
    }

    /// True when a rate string represents (near) zero, for dimming idle values.
    static func isZeroRate(_ bytesPerSec: Double) -> Bool { bytesPerSec < 1 }

    static func temperature(_ celsius: Double, unit: TemperatureUnit = .system) -> String {
        switch unit.resolved {
        case .fahrenheit: return "\(Int((celsius * 9 / 5 + 32).rounded()))°F"
        default:          return "\(Int(celsius.rounded()))°C"
        }
    }

    static func value(_ value: Double, unit: String) -> String {
        let rounded = (value * 10).rounded() / 10
        if unit == "RPM" {
            return "\(Int(value.rounded())) \(unit)"
        }
        return "\(rounded) \(unit)"
    }

    static func duration(minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}
