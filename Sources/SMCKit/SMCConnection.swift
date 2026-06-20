import Foundation
import CSMC

/// Read-only client for the AppleSMC service.
///
/// The ABI-sensitive `IOConnectCallStructMethod` plumbing lives in the `CSMC` C target,
/// where the `SMCParamStruct` layout exactly matches what the kernel expects (Swift's
/// own struct layout does not). This type is a thin, safe Swift wrapper over it.
public final class SMCConnection {
    private let conn: UInt32

    public init?() {
        let c = csmc_open()
        guard c != 0 else { return nil }
        conn = c
    }

    deinit { csmc_close(conn) }

    /// Reads a key and returns its SMC data type and raw bytes. Read-only.
    public func read(_ key: String) -> SMCValue? {
        guard let fourcc = FourCC.encode(key) else { return nil }
        var type: UInt32 = 0
        var size: UInt32 = 0
        var bytes = [UInt8](repeating: 0, count: 32)
        let rc = bytes.withUnsafeMutableBufferPointer {
            csmc_read(conn, fourcc, &type, &size, $0.baseAddress)
        }
        guard rc == 0 else { return nil }
        let n = Int(min(size, 32))
        return SMCValue(key: key, type: FourCC.decode(type), bytes: Array(bytes.prefix(n)))
    }

    /// Total number of keys exposed by this SMC (via the `#KEY` meta-key).
    public func keyCount() -> Int {
        Int(read("#KEY")?.uint32 ?? 0)
    }

    /// Returns the FourCC key name at a given enumeration index.
    public func key(atIndex index: Int) -> String? {
        let k = csmc_key_from_index(conn, UInt32(index))
        return k == 0 ? nil : FourCC.string(from: k)
    }

    /// Enumerates every key name exposed by the SMC. Expensive — call once and cache.
    public func allKeys() -> [String] {
        let count = keyCount()
        guard count > 0 else { return [] }
        var keys: [String] = []
        keys.reserveCapacity(count)
        for i in 0..<count {
            if let name = key(atIndex: i) { keys.append(name) }
        }
        return keys
    }
}
