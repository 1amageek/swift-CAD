public struct PortableIdentity128: Hashable, Sendable, Comparable, CustomStringConvertible {
    public let high: UInt64
    public let low: UInt64

    public init() {
        var generator = SystemRandomNumberGenerator()
        self.init(randomUsing: &generator)
    }

    public init(high: UInt64, low: UInt64) {
        self.high = high
        self.low = low
    }

    public init(randomUsing generator: inout SystemRandomNumberGenerator) {
        var high = generator.next()
        var low = generator.next()
        high = (high & 0xFFFF_FFFF_FFFF_0FFF) | 0x0000_0000_0000_4000
        low = (low & 0x3FFF_FFFF_FFFF_FFFF) | 0x8000_0000_0000_0000
        self.init(high: high, low: low)
    }

    public init(canonicalString: String) throws {
        let bytes = Array(canonicalString.utf8)
        guard bytes.count == 36,
              bytes[8] == 45,
              bytes[13] == 45,
              bytes[18] == 45,
              bytes[23] == 45 else {
            throw PortableIdentityError.invalidCanonicalString
        }

        var octets = [UInt8]()
        octets.reserveCapacity(16)
        var hasHighNibble = false
        for index in 0..<36 where index != 8 && index != 13 && index != 18 && index != 23 {
            guard let value = Self.hexValue(bytes[index]) else {
                throw PortableIdentityError.invalidCanonicalString
            }
            if !hasHighNibble {
                octets.append(value << 4)
                hasHighNibble = true
            } else {
                octets[octets.count - 1] |= value
                hasHighNibble = false
            }
        }
        guard octets.count == 16, !hasHighNibble else {
            throw PortableIdentityError.invalidCanonicalString
        }

        var high: UInt64 = 0
        var low: UInt64 = 0
        for index in 0..<8 {
            high = (high << 8) | UInt64(octets[index])
        }
        for index in 8..<16 {
            low = (low << 8) | UInt64(octets[index])
        }
        self.init(high: high, low: low)
    }

    public var canonicalString: String {
        let bytes = [
            Self.byte(high, 56), Self.byte(high, 48), Self.byte(high, 40), Self.byte(high, 32),
            Self.byte(high, 24), Self.byte(high, 16), Self.byte(high, 8), Self.byte(high, 0),
            Self.byte(low, 56), Self.byte(low, 48), Self.byte(low, 40), Self.byte(low, 32),
            Self.byte(low, 24), Self.byte(low, 16), Self.byte(low, 8), Self.byte(low, 0)
        ]
        var result = [UInt8]()
        result.reserveCapacity(36)
        for index in 0..<bytes.count {
            if index == 4 || index == 6 || index == 8 || index == 10 {
                result.append(45)
            }
            let value = bytes[index]
            result.append(Self.hexDigits[Int(value >> 4)])
            result.append(Self.hexDigits[Int(value & 0x0F)])
        }
        return String(decoding: result, as: UTF8.self)
    }

    public var description: String { canonicalString }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.high != rhs.high { return lhs.high < rhs.high }
        return lhs.low < rhs.low
    }

    private static let hexDigits: [UInt8] = Array("0123456789ABCDEF".utf8)

    private static func hexValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 48...57: byte - 48
        case 65...70: byte - 55
        case 97...102: byte - 87
        default: nil
        }
    }

    private static func byte(_ value: UInt64, _ shift: UInt64) -> UInt8 {
        UInt8(truncatingIfNeeded: value >> shift)
    }
}
