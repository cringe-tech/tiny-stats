import Foundation
import SMCKit

// Pure, dependency-light model for fan control: the temperature→fan-speed curve, the named
// presets, and the sensor source the curve reads. Kept free of XPC/timers so it can be unit
// tested in TinyStatsSelfTest without root or hardware.

/// One control point on a fan curve: at `tempC` the fan runs at `percent` of its usable range.
public struct CurvePoint: Codable, Sendable, Equatable {
    public var tempC: Double
    public var percent: Double      // 0…100, mapped to [minRPM, maxRPM] per fan

    public init(tempC: Double, percent: Double) {
        self.tempC = tempC
        self.percent = percent
    }
}

/// A temperature→percent fan curve. Points are kept sorted by temperature; lookup is a
/// clamped linear interpolation (flat below the first point and above the last).
public struct FanCurve: Codable, Sendable, Equatable {
    public var points: [CurvePoint]

    public init(points: [CurvePoint]) {
        self.points = points.sorted { $0.tempC < $1.tempC }
    }

    /// Fan percent (0…100) for a temperature, clamped at the curve's ends.
    public func percent(atTemp t: Double) -> Double {
        guard let first = points.first else { return 0 }
        guard let last = points.last else { return 0 }
        if t <= first.tempC { return clampPercent(first.percent) }
        if t >= last.tempC { return clampPercent(last.percent) }
        for i in 1..<points.count {
            let a = points[i - 1], b = points[i]
            if t <= b.tempC {
                let span = b.tempC - a.tempC
                guard span > 0 else { return clampPercent(b.percent) }
                let f = (t - a.tempC) / span
                return clampPercent(a.percent + f * (b.percent - a.percent))
            }
        }
        return clampPercent(last.percent)
    }

    private func clampPercent(_ p: Double) -> Double { Swift.min(100, Swift.max(0, p)) }
}

/// User-facing fan profiles. Each non-`auto` preset is just a predefined curve; `custom` uses
/// the user's edited curve (stored separately in settings).
public enum FanPreset: String, Codable, CaseIterable, Sendable, Identifiable {
    case auto          // hand control back to macOS
    case coolTouch     // "keep the chassis cool to the touch" — ramps early and hard
    case balanced      // moderate
    case turbo         // full speed
    case custom        // user-drawn curve

    public var id: String { rawValue }

    /// The built-in curve for this preset, or nil for `.auto` (no control) and `.custom`
    /// (caller supplies the stored curve).
    public var builtInCurve: FanCurve? {
        switch self {
        case .auto, .custom:
            return nil
        case .coolTouch:
            return FanCurve(points: [
                .init(tempC: 40, percent: 30), .init(tempC: 50, percent: 55),
                .init(tempC: 60, percent: 80), .init(tempC: 70, percent: 100),
            ])
        case .balanced:
            return FanCurve(points: [
                .init(tempC: 45, percent: 20), .init(tempC: 60, percent: 45),
                .init(tempC: 75, percent: 80), .init(tempC: 85, percent: 100),
            ])
        case .turbo:
            return FanCurve(points: [.init(tempC: 30, percent: 100), .init(tempC: 100, percent: 100)])
        }
    }
}

/// Which temperature drives the curve.
public enum FanSensorSource: String, Codable, CaseIterable, Sendable, Identifiable {
    case cpu
    case gpu
    case powerBattery  // hotter of the power-delivery / battery sensors (matters while charging)

    public var id: String { rawValue }
}

public enum FanModel {
    /// A sensible default custom curve, shown when the user first switches to Custom.
    public static let defaultCustomCurve = FanCurve(points: [
        .init(tempC: 45, percent: 25), .init(tempC: 60, percent: 50),
        .init(tempC: 75, percent: 80), .init(tempC: 90, percent: 100),
    ])

    /// Temperature in °C that drives the curve, derived from a set of sensor readings.
    /// `.cpu`/`.gpu` average the component's sensors (same grouping as the Sensors panel);
    /// `.powerBattery` takes the hotter of the power-delivery and battery sensors — that's the
    /// area that heats up while charging from a low state, where extra cooling helps.
    public static func sourceTemperature(from readings: [SensorReading],
                                         source: FanSensorSource) -> Double? {
        let temps = readings.filter { $0.category == .temperature }
        guard !temps.isEmpty else { return nil }
        switch source {
        case .powerBattery:
            // Power-delivery sensors (classified `.power`) plus battery sensors (`TB…` keys).
            let relevant = temps.filter {
                SensorClassifier.component(forKey: $0.key) == .power || $0.key.hasPrefix("TB")
            }
            guard let hottest = relevant.map(\.value).max() else {
                return temps.map(\.value).max()                  // fall back to hottest overall
            }
            return hottest
        case .cpu, .gpu:
            let component: TempComponent = (source == .cpu) ? .cpu : .gpu
            let matched = temps.filter { SensorClassifier.component(forKey: $0.key) == component }
            guard !matched.isEmpty else { return temps.map(\.value).max() }   // fall back to hottest
            return matched.map(\.value).reduce(0, +) / Double(matched.count)
        }
    }

    /// Maps a curve percent (0…100) to an RPM in a fan's usable range.
    public static func rpm(forPercent percent: Double, min: Double, max: Double) -> Double {
        let p = Swift.min(100, Swift.max(0, percent)) / 100
        return min + p * (max - min)
    }
}
