import Foundation
import Darwin

/// Network throughput from `getifaddrs` link-layer byte counters, differentiated over time.
public final class NetworkCollector {
    private var lastIn: UInt64 = 0
    private var lastOut: UInt64 = 0
    private var lastTime: Date?

    init() {}

    /// Pure delta math, exposed for unit testing.
    public static func rate(
        previousIn: UInt64, previousOut: UInt64,
        currentIn: UInt64, currentOut: UInt64,
        seconds: Double
    ) -> NetworkUsage {
        guard seconds > 0 else { return NetworkUsage() }
        let down = currentIn >= previousIn ? Double(currentIn - previousIn) / seconds : 0
        let up = currentOut >= previousOut ? Double(currentOut - previousOut) / seconds : 0
        return NetworkUsage(uploadBytesPerSec: up, downloadBytesPerSec: down)
    }

    func sample() -> NetworkUsage {
        let (bytesIn, bytesOut) = Self.totalBytes()
        let now = Date()
        defer { lastIn = bytesIn; lastOut = bytesOut; lastTime = now }
        guard let lastTime else { return NetworkUsage() }
        return Self.rate(
            previousIn: lastIn, previousOut: lastOut,
            currentIn: bytesIn, currentOut: bytesOut,
            seconds: now.timeIntervalSince(lastTime))
    }

    /// Sums byte counters across physical interfaces, skipping loopback.
    private static func totalBytes() -> (UInt64, UInt64) {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return (0, 0) }
        defer { freeifaddrs(head) }

        var totalIn: UInt64 = 0
        var totalOut: UInt64 = 0
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let cur = ptr {
            defer { ptr = cur.pointee.ifa_next }
            guard let addr = cur.pointee.ifa_addr,
                  addr.pointee.sa_family == UInt8(AF_LINK) else { continue }
            let name = String(cString: cur.pointee.ifa_name)
            if name.hasPrefix("lo") { continue }
            guard let data = cur.pointee.ifa_data else { continue }
            let networkData = data.assumingMemoryBound(to: if_data.self)
            totalIn += UInt64(networkData.pointee.ifi_ibytes)
            totalOut += UInt64(networkData.pointee.ifi_obytes)
        }
        return (totalIn, totalOut)
    }
}
