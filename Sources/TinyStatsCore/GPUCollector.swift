import Foundation
import IOKit

/// GPU utilization from the accelerator's `PerformanceStatistics` dictionary.
/// Works on Apple Silicon, where the integrated GPU reports `Device Utilization %`.
final class GPUCollector {
    func sample() -> GPUUsage {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator
        ) == KERN_SUCCESS else { return GPUUsage() }
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
        return GPUUsage(utilization: min(1, best / 100))
    }
}
