public struct USDCCrateField: Sendable, Equatable, Hashable {
    public var tokenIndex: UInt32
    public var valueRep: USDCCrateValueRep

    public init(tokenIndex: UInt32, valueRep: USDCCrateValueRep) {
        self.tokenIndex = tokenIndex
        self.valueRep = valueRep
    }
}
