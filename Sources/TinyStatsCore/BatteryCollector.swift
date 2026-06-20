import Foundation
import IOKit
import IOKit.ps

/// Battery state from the IOPowerSources API, enriched with cycle count and health
/// from the `AppleSmartBattery` registry entry. Returns nil on machines without a battery.
final class BatteryCollector {
    func sample() -> BatteryInfo? {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
              let source = sources.first,
              let desc = IOPSGetPowerSourceDescription(snapshot, source)?
                  .takeUnretainedValue() as? [String: Any]
        else { return nil }

        var info = BatteryInfo()
        let current = (desc[kIOPSCurrentCapacityKey] as? Int) ?? 0
        let max = (desc[kIOPSMaxCapacityKey] as? Int) ?? 100
        info.charge = max == 0 ? 0 : Double(current) / Double(max)
        info.isCharging = (desc[kIOPSIsChargingKey] as? Bool) ?? false
        info.isPluggedIn = (desc[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
        if let minutes = desc[kIOPSTimeToEmptyKey] as? Int, minutes > 0, !info.isCharging {
            info.timeToEmptyMinutes = minutes
        }

        enrichFromRegistry(&info)
        return info
    }

    private func enrichFromRegistry(_ info: inout BatteryInfo) {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }

        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0)
            == KERN_SUCCESS, let props = unmanaged?.takeRetainedValue() as? [String: Any]
        else { return }

        info.cycleCount = props["CycleCount"] as? Int
        let maxCap = (props["AppleRawMaxCapacity"] as? Int) ?? (props["MaxCapacity"] as? Int)
        let designCap = props["DesignCapacity"] as? Int
        if let maxCap, let designCap, designCap > 0 {
            info.healthFraction = Double(maxCap) / Double(designCap)
        }
    }
}
