import Foundation
import IOKit

/// GPU utilization from the accelerator's `PerformanceStatistics` dictionary.
/// Works on Apple Silicon, where the integrated GPU reports `Device Utilization %`.
final class GPUCollector {
    private var lastTime: Date?
    private var lastUsage = GPUUsage()

    func sample() -> GPUUsage {
        // A forced refresh (e.g. opening the popover) can land between the accelerator's
        // own counter updates and read back as 0%. Hold the last value when sampled below
        // the minimum window so the cell doesn't flash to 0.
        let now = Date()
        if let lastTime, now.timeIntervalSince(lastTime) < MetricRate.minSampleInterval {
            return lastUsage
        }

        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator
        ) == KERN_SUCCESS else { return lastUsage }
        defer { IOObjectRelease(iterator) }

        var best = 0.0
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer { IOObjectRelease(service); service = IOIteratorNext(iterator) }
            var unmanaged: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0)
                == KERN_SUCCESS, let props = unmanaged?.takeRetainedValue() as? [String: Any],
                let stats = props["PerformanceStatistics"] as? [String: Any] else { continue }

            let candidates = ["Device Utilization %", "GPU Activity(%)", "GPU Core Utilization"]
            for key in candidates {
                if let number = stats[key] as? NSNumber {
                    // Core utilization is reported in nanoseconds-scaled form on some chips;
                    // the "%" keys are already 0...100.
                    let value = key.contains("%") ? number.doubleValue : number.doubleValue / 1.0
                    best = max(best, value)
                }
            }
        }
        let usage = GPUUsage(utilization: min(1, best / 100))
        lastTime = now
        lastUsage = usage
        return usage
    }
}
