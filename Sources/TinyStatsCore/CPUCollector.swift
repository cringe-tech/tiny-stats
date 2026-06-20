import Foundation
import Darwin

/// CPU usage from per-core tick deltas (`host_processor_info` / `PROCESSOR_CPU_LOAD_INFO`).
public final class CPUCollector {
    private var previous: [host_cpu_load_info] = []

    init() {}

    /// Splits delta logic out so it can be unit-tested without touching the host.
    public static func usage(previous: [host_cpu_load_info], current: [host_cpu_load_info]) -> CPUUsage {
        guard !current.isEmpty, previous.count == current.count else {
            return CPUUsage()
        }
        var totalUser = 0.0, totalSystem = 0.0, totalIdle = 0.0, totalAll = 0.0
        var perCore: [Double] = []
        perCore.reserveCapacity(current.count)

        for (prev, cur) in zip(previous, current) {
            let user = Double(cur.cpu_ticks.0 &- prev.cpu_ticks.0)   // USER
            let system = Double(cur.cpu_ticks.1 &- prev.cpu_ticks.1) // SYSTEM
            let idle = Double(cur.cpu_ticks.2 &- prev.cpu_ticks.2)   // IDLE
            let nice = Double(cur.cpu_ticks.3 &- prev.cpu_ticks.3)   // NICE
            let busy = user + system + nice
            let total = busy + idle
            perCore.append(total > 0 ? busy / total : 0)
            totalUser += user + nice
            totalSystem += system
            totalIdle += idle
            totalAll += total
        }

        guard totalAll > 0 else { return CPUUsage(system: 0, user: 0, idle: 1, perCore: perCore) }
        return CPUUsage(
            system: totalSystem / totalAll,
            user: totalUser / totalAll,
            idle: totalIdle / totalAll,
            perCore: perCore)
    }

    func sample() -> CPUUsage {
        let current = Self.hostLoadInfo()
        defer { previous = current }
        guard !previous.isEmpty else { return CPUUsage() }
        return Self.usage(previous: previous, current: current)
    }

    private static func hostLoadInfo() -> [host_cpu_load_info] {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0

        let result = host_processor_info(
            mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount)
        guard result == KERN_SUCCESS, let info else { return [] }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info),
                          vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride))
        }

        var loads: [host_cpu_load_info] = []
        loads.reserveCapacity(Int(cpuCount))
        let ticksPerCPU = MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride
        info.withMemoryRebound(to: integer_t.self, capacity: Int(infoCount)) { base in
            for i in 0..<Int(cpuCount) {
                var entry = host_cpu_load_info()
                entry.cpu_ticks.0 = UInt32(bitPattern: base[i * ticksPerCPU + 0])
                entry.cpu_ticks.1 = UInt32(bitPattern: base[i * ticksPerCPU + 1])
                entry.cpu_ticks.2 = UInt32(bitPattern: base[i * ticksPerCPU + 2])
                entry.cpu_ticks.3 = UInt32(bitPattern: base[i * ticksPerCPU + 3])
                loads.append(entry)
            }
        }
        return loads
    }
}
