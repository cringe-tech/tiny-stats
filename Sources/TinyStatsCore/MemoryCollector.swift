import Foundation
import Darwin

/// Memory usage from `host_statistics64` (vm_statistics64).
final class MemoryCollector {
    private var lastTime: Date?
    private var lastUsage = MemoryUsage()
    private let pageSize: UInt64 = {
        var size: vm_size_t = 0
        host_page_size(mach_host_self(), &size)
        return UInt64(size)
    }()

    func sample() -> MemoryUsage {
        // A forced refresh (e.g. opening the popover) shouldn't make the menu-bar cell jump on
        // click. Hold the last value when sampled below the minimum window, like the rate collectors.
        let now = Date()
        if let lastTime, now.timeIntervalSince(lastTime) < MetricRate.minSampleInterval {
            return lastUsage
        }

        let total = ProcessInfo.processInfo.physicalMemory
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)

        let result = withUnsafeMutablePointer(to: &stats) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return lastUsage }

        // "App memory" model used by Activity Monitor: active + wired + compressed.
        let active = UInt64(stats.active_count) * pageSize
        let wired = UInt64(stats.wire_count) * pageSize
        let compressed = UInt64(stats.compressor_page_count) * pageSize
        let used = active + wired + compressed
        let pressure = total == 0 ? 0 : Double(wired + compressed) / Double(total)

        let usage = MemoryUsage(totalBytes: total, usedBytes: used, pressure: min(1, pressure))
        lastTime = now
        lastUsage = usage
        return usage
    }
}
