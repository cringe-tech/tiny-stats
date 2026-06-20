import Foundation
import Darwin

/// Per-process CPU / memory / disk usage via `libproc`. Works for the current user's
/// processes without elevated privileges (others are skipped). CPU and disk are deltas,
/// so two samples are needed before they read non-zero.
final class ProcessSampler {
    private struct Prev {
        var cpuTimeNs: UInt64
        var diskBytes: UInt64
    }
    private var previous: [Int32: Prev] = [:]
    private var lastTime: Date?

    func sample() -> [ProcessUsage] {
        let pids = Self.allPIDs()
        guard !pids.isEmpty else { return [] }

        let now = Date()
        let seconds = lastTime.map { now.timeIntervalSince($0) } ?? 0
        defer { lastTime = now }

        var result: [ProcessUsage] = []
        var current: [Int32: Prev] = [:]
        result.reserveCapacity(pids.count)

        for pid in pids where pid > 0 {
            guard let info = Self.rusage(pid) else { continue }
            let cpuTimeNs = info.ri_user_time &+ info.ri_system_time
            let diskBytes = info.ri_diskio_bytesread &+ info.ri_diskio_byteswritten
            current[pid] = Prev(cpuTimeNs: cpuTimeNs, diskBytes: diskBytes)

            var cpu = 0.0
            var diskRate = 0.0
            if seconds > 0, let prev = previous[pid] {
                let cpuDeltaNs = cpuTimeNs >= prev.cpuTimeNs ? Double(cpuTimeNs - prev.cpuTimeNs) : 0
                cpu = cpuDeltaNs / (seconds * 1_000_000_000)
                let diskDelta = diskBytes >= prev.diskBytes ? Double(diskBytes - prev.diskBytes) : 0
                diskRate = diskDelta / seconds
            }

            result.append(ProcessUsage(
                id: pid,
                name: Self.name(pid),
                cpu: cpu,
                memoryBytes: info.ri_phys_footprint,
                diskBytesPerSec: diskRate))
        }

        previous = current
        return result
    }

    // MARK: libproc plumbing

    private static func allPIDs() -> [Int32] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) + 32)
        let size = Int32(pids.count * MemoryLayout<pid_t>.size)
        let written = proc_listallpids(&pids, size)
        guard written > 0 else { return [] }
        return Array(pids.prefix(Int(written)))
    }

    private static func rusage(_ pid: Int32) -> rusage_info_v4? {
        let buffer = UnsafeMutablePointer<rusage_info_v4>.allocate(capacity: 1)
        defer { buffer.deallocate() }
        let rc = buffer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
            proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
        }
        return rc == 0 ? buffer.pointee : nil
    }

    private static func name(_ pid: Int32) -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        let length = proc_name(pid, &buffer, UInt32(buffer.count))
        if length > 0 {
            return String(cString: buffer)
        }
        return "pid \(pid)"
    }
}
