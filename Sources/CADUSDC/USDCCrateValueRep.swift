public struct USDCCrateValueRep: Sendable, Equatable, Hashable {
    public static let isArrayBit: UInt64 = 1 << 63
    public static let isInlinedBit: UInt64 = 1 << 62
    public static let isCompressedBit: UInt64 = 1 << 61
    public static let isArrayEditBit: UInt64 = 1 << 60
    public static let payloadMask: UInt64 = (1 << 48) - 1

    public var rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public init(type: USDCCrateValueType, isInlined: Bool, isArray: Bool, payload: UInt64) {
        rawValue = (isArray ? Self.isArrayBit : 0)
            | (isInlined ? Self.isInlinedBit : 0)
            | (UInt64(type.rawValue) << 48)
            | (payload & Self.payloadMask)
    }

    public var isArray: Bool {
        rawValue & Self.isArrayBit != 0
    }

    public var isInlined: Bool {
        rawValue & Self.isInlinedBit != 0
    }

    public var isCompressed: Bool {
        rawValue & Self.isCompressedBit != 0
    }

    public var isArrayEdit: Bool {
        rawValue & Self.isArrayEditBit != 0
    }

    public var rawType: UInt8 {
        UInt8((rawValue >> 48) & 0xff)
    }

    public var type: USDCCrateValueType? {
        USDCCrateValueType(rawValue: rawType)
    }

    public var payload: UInt64 {
        rawValue & Self.payloadMask
    }
}
