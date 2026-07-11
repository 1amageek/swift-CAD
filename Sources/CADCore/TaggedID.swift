import Foundation

public struct TaggedID<Tag>: Hashable, Codable, Sendable, Comparable, CustomStringConvertible {
    private let high: UInt64
    private let low: UInt64

    public init(_ rawValue: UUID = UUID()) {
        let bytes = rawValue.uuid
        high = Self.word(
            bytes.0, bytes.1, bytes.2, bytes.3,
            bytes.4, bytes.5, bytes.6, bytes.7
        )
        low = Self.word(
            bytes.8, bytes.9, bytes.10, bytes.11,
            bytes.12, bytes.13, bytes.14, bytes.15
        )
    }

    package init(highBits: UInt64, lowBits: UInt64) {
        high = highBits
        low = lowBits
    }

    package var bitPattern: (high: UInt64, low: UInt64) {
        (high, low)
    }

    public var rawValue: UUID {
        UUID(uuid: (
            Self.byte(high, 56), Self.byte(high, 48),
            Self.byte(high, 40), Self.byte(high, 32),
            Self.byte(high, 24), Self.byte(high, 16),
            Self.byte(high, 8), Self.byte(high, 0),
            Self.byte(low, 56), Self.byte(low, 48),
            Self.byte(low, 40), Self.byte(low, 32),
            Self.byte(low, 24), Self.byte(low, 16),
            Self.byte(low, 8), Self.byte(low, 0)
        ))
    }

    public var description: String {
        rawValue.uuidString
    }

    public static func < (lhs: TaggedID<Tag>, rhs: TaggedID<Tag>) -> Bool {
        if lhs.high != rhs.high {
            return lhs.high < rhs.high
        }
        return lhs.low < rhs.low
    }

    public static func == (lhs: TaggedID<Tag>, rhs: TaggedID<Tag>) -> Bool {
        lhs.high == rhs.high && lhs.low == rhs.low
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(high)
        hasher.combine(low)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard let uuid = UUID(uuidString: value) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid UUID string for tagged ID."
            )
        }
        self.init(uuid)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue.uuidString)
    }

    private static func word(
        _ byte0: UInt8,
        _ byte1: UInt8,
        _ byte2: UInt8,
        _ byte3: UInt8,
        _ byte4: UInt8,
        _ byte5: UInt8,
        _ byte6: UInt8,
        _ byte7: UInt8
    ) -> UInt64 {
        (UInt64(byte0) << 56)
            | (UInt64(byte1) << 48)
            | (UInt64(byte2) << 40)
            | (UInt64(byte3) << 32)
            | (UInt64(byte4) << 24)
            | (UInt64(byte5) << 16)
            | (UInt64(byte6) << 8)
            | UInt64(byte7)
    }

    private static func byte(_ value: UInt64, _ shift: UInt64) -> UInt8 {
        UInt8(truncatingIfNeeded: value >> shift)
    }
}
