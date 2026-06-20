import Foundation

/// Helpers to convert between 4-character SMC key names and their UInt32 FourCC encoding.
public enum FourCC {
    public static func encode(_ string: String) -> UInt32? {
        let scalars = Array(string.utf8)
        guard scalars.count == 4 else { return nil }
        return (UInt32(scalars[0]) << 24) | (UInt32(scalars[1]) << 16)
            | (UInt32(scalars[2]) << 8) | UInt32(scalars[3])
    }

    public static func string(from value: UInt32) -> String {
        let bytes = [
            UInt8((value >> 24) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff),
        ]
        return String(bytes: bytes, encoding: .ascii) ?? ""
    }

    /// Decodes a data-type FourCC, trimming trailing spaces (e.g. `"flt "` -> `"flt"`).
    public static func decode(_ value: UInt32) -> String {
        string(from: value).trimmingCharacters(in: .whitespaces)
    }
}

/// A decoded SMC reading: its key, SMC data type, and raw bytes.
public struct SMCValue: Sendable {
    public let key: String
    public let type: String
    public let bytes: [UInt8]

    public init(key: String, type: String, bytes: [UInt8]) {
        self.key = key
        self.type = type
        self.bytes = bytes
    }

    public var uint32: UInt32? {
        guard bytes.count >= 4 else { return nil }
        return (UInt32(bytes[0]) << 24) | (UInt32(bytes[1]) << 16)
            | (UInt32(bytes[2]) << 8) | UInt32(bytes[3])
    }

    /// Interprets the raw bytes as a Double according to the SMC data type.
    /// Covers the encodings actually emitted on Apple Silicon and Intel SMCs.
    public var double: Double? {
        switch type {
        case "flt":
            guard bytes.count >= 4 else { return nil }
            let bits = UInt32(bytes[0]) | (UInt32(bytes[1]) << 8)
                | (UInt32(bytes[2]) << 16) | (UInt32(bytes[3]) << 24)
            return Double(Float(bitPattern: bits))
        case "ui8":
            guard let b = bytes.first else { return nil }
            return Double(b)
        case "ui16":
            guard bytes.count >= 2 else { return nil }
            return Double((UInt16(bytes[0]) << 8) | UInt16(bytes[1]))
        case "ui32":
            return uint32.map(Double.init)
        case "si8":
            guard let b = bytes.first else { return nil }
            return Double(Int8(bitPattern: b))
        case "si16":
            guard bytes.count >= 2 else { return nil }
            let raw = (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
            return Double(Int16(bitPattern: raw))
        case "sp78":
            guard bytes.count >= 2 else { return nil }
            let raw = (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
            return Double(Int16(bitPattern: raw)) / 256.0
        case "fpe2":
            guard bytes.count >= 2 else { return nil }
            return Double((UInt16(bytes[0]) << 8) | UInt16(bytes[1])) / 4.0
        case "fp2e":
            guard bytes.count >= 2 else { return nil }
            return Double((UInt16(bytes[0]) << 8) | UInt16(bytes[1])) / 16384.0
        default:
            // Best effort: a 4-byte float covers most unknown Apple Silicon sensors.
            if bytes.count >= 4 {
                let bits = UInt32(bytes[0]) | (UInt32(bytes[1]) << 8)
                    | (UInt32(bytes[2]) << 16) | (UInt32(bytes[3]) << 24)
                return Double(Float(bitPattern: bits))
            }
            return nil
        }
    }
}
