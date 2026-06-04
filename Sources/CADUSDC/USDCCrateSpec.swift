public struct USDCCrateSpec: Sendable, Equatable, Hashable {
    public var pathIndex: UInt32
    public var fieldSetIndex: UInt32
    public var specType: USDCCrateSpecType

    public init(pathIndex: UInt32, fieldSetIndex: UInt32, specType: USDCCrateSpecType) {
        self.pathIndex = pathIndex
        self.fieldSetIndex = fieldSetIndex
        self.specType = specType
    }
}
