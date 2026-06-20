import Foundation
import SMCKit

public struct CPUUsage: Sendable, Equatable {
    public var system: Double = 0   // 0...1
    public var user: Double = 0     // 0...1
    public var idle: Double = 1     // 0...1
    public var total: Double { min(1, system + user) }
    public var perCore: [Double] = []
}

public struct MemoryUsage: Sendable, Equatable {
    public var totalBytes: UInt64 = 0
    public var usedBytes: UInt64 = 0
    public var pressure: Double = 0   // 0...1
    public var fraction: Double {
        totalBytes == 0 ? 0 : Double(usedBytes) / Double(totalBytes)
    }
}

public struct NetworkUsage: Sendable, Equatable {
    public var uploadBytesPerSec: Double = 0
    public var downloadBytesPerSec: Double = 0
}

public struct DiskUsage: Sendable, Equatable {
    public var totalBytes: UInt64 = 0
    public var freeBytes: UInt64 = 0
    public var readBytesPerSec: Double = 0
    public var writeBytesPerSec: Double = 0
    public var usedBytes: UInt64 { totalBytes >= freeBytes ? totalBytes - freeBytes : 0 }
    public var fraction: Double {
        totalBytes == 0 ? 0 : Double(usedBytes) / Double(totalBytes)
    }
}

public struct GPUUsage: Sendable, Equatable {
    public var utilization: Double = 0   // 0...1
}

public struct BatteryInfo: Sendable, Equatable {
    public var charge: Double = 0        // 0...1
    public var isCharging: Bool = false
    public var isPluggedIn: Bool = false
    public var timeToEmptyMinutes: Int?  // nil if unknown / charging
    public var cycleCount: Int?
    public var healthFraction: Double?   // maxCapacity / designCapacity
}

public struct ProcessUsage: Sendable, Identifiable, Equatable {
    public var id: Int32         // pid
    public var name: String
    public var cpu: Double       // fraction of one core (1.0 = 100% of a core)
    public var memoryBytes: UInt64
    public var diskBytesPerSec: Double
}

/// Optional collectors that can be switched off when their metric is hidden, so no
/// data is gathered for inactive metrics. CPU and memory are always sampled (cheap,
/// and the menu bar's default cell needs CPU).
public enum MetricKind: String, Sendable, CaseIterable {
    case network, disk, gpu, battery
}

public struct MetricsSnapshot: Sendable {
    public init() {}

    public var date = Date()
    public var cpu = CPUUsage()
    public var memory = MemoryUsage()
    public var network = NetworkUsage()
    public var disk = DiskUsage()
    public var gpu = GPUUsage()
    public var battery: BatteryInfo?
    public var sensors: [SensorReading] = []
    public var processes: [ProcessUsage] = []
}
