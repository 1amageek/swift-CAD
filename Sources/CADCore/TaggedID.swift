#if !hasFeature(Embedded)
import Foundation
#endif

public struct TaggedID<Tag>: Hashable, Sendable, Comparable, CustomStringConvertible {
    private let identity: PortableIdentity128

    public init() {
        identity = PortableIdentity128()
    }

    public init(_ rawValue: PortableIdentity128) {
        identity = rawValue
    }

    #if !hasFeature(Embedded)
    public init(_ rawValue: UUID) {
        identity = PortableIdentity128(
            high: Self.word(
                rawValue.uuid.0, rawValue.uuid.1, rawValue.uuid.2, rawValue.uuid.3,
                rawValue.uuid.4, rawValue.uuid.5, rawValue.uuid.6, rawValue.uuid.7
            ),
            low: Self.word(
                rawValue.uuid.8, rawValue.uuid.9, rawValue.uuid.10, rawValue.uuid.11,
                rawValue.uuid.12, rawValue.uuid.13, rawValue.uuid.14, rawValue.uuid.15
            )
        )
    }
    #endif

    package init(highBits: UInt64, lowBits: UInt64) {
        identity = PortableIdentity128(high: highBits, low: lowBits)
    }

    package var bitPattern: (high: UInt64, low: UInt64) {
        (identity.high, identity.low)
    }

    public var rawValue: PortableIdentity128 { identity }

    public var description: String { identity.canonicalString }

    public static func < (lhs: TaggedID<Tag>, rhs: TaggedID<Tag>) -> Bool {
        lhs.identity < rhs.identity
    }

    public static func == (lhs: TaggedID<Tag>, rhs: TaggedID<Tag>) -> Bool {
        lhs.identity == rhs.identity
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(identity.high)
        hasher.combine(identity.low)
    }

    #if !hasFeature(Embedded)
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
    #endif
}

#if !hasFeature(Embedded)
extension TaggedID: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        do {
            self.init(try PortableIdentity128(canonicalString: value))
        } catch PortableIdentityError.invalidCanonicalString {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid UUID string for tagged ID."
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(identity.canonicalString)
    }
}
#endif
