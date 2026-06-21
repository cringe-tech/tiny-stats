import Foundation
import IOKit

/// Disk capacity (`URLResourceValues`) plus read/write throughput from
/// `IOBlockStorageDriver` statistics, differentiated over time.
final class DiskCollector {
    private var lastRead: UInt64 = 0
    private var lastWrite: UInt64 = 0
    private var lastTime: Date?
    private var lastRates: (read: Double, write: Double) = (0, 0)

    func sample() -> DiskUsage {
        var usage = DiskUsage()
        let url = URL(fileURLWithPath: "/")
        if let values = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey, .volumeAvailableCapacityKey
        ]) {
            usage.totalBytes = UInt64(values.volumeTotalCapacity ?? 0)
            usage.freeBytes = UInt64(values.volumeAvailableCapacity ?? 0)
        }

        let (read, write) = Self.ioBytes()
        let now = Date()
        if let lastTime {
            let seconds = now.timeIntervalSince(lastTime)
            // Too short a window (back-to-back forced refresh) can't measure throughput; carry
            // the last rates forward and keep the baseline so the next real tick is accurate.
            if seconds < MetricRate.minSampleInterval {
                usage.readBytesPerSec = lastRates.read
                usage.writeBytesPerSec = lastRates.write
                return usage
            }
            usage.readBytesPerSec = read >= lastRead ? Double(read - lastRead) / seconds : 0
            usage.writeBytesPerSec = write >= lastWrite ? Double(write - lastWrite) / seconds : 0
        }
        lastRead = read; lastWrite = write; lastTime = now
        lastRates = (usage.readBytesPerSec, usage.writeBytesPerSec)
        return usage
    }

    private static func ioBytes() -> (UInt64, UInt64) {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator
        ) == KERN_SUCCESS else { return (0, 0) }
        defer { IOObjectRelease(iterator) }

        var totalRead: UInt64 = 0
        var totalWrite: UInt64 = 0
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer { IOObjectRelease(service); service = IOIteratorNext(iterator) }
            guard let props = copyProperties(service),
                  let stats = props["Statistics"] as? [String: Any] else { continue }
            totalRead += (stats["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
            totalWrite += (stats["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
        }
        return (totalRead, totalWrite)
    }

    private static func copyProperties(_ service: io_object_t) -> [String: Any]? {
        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0)
            == KERN_SUCCESS, let dict = unmanaged?.takeRetainedValue() else { return nil }
        return dict as? [String: Any]
    }
}
