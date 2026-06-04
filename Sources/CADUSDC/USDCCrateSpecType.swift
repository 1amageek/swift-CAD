public enum USDCCrateSpecType: UInt32, Sendable, Equatable, CaseIterable {
    case unknown = 0
    case attribute = 1
    case connection = 2
    case expression = 3
    case mapper = 4
    case mapperArgument = 5
    case prim = 6
    case pseudoRoot = 7
    case relationship = 8
    case relationshipTarget = 9
    case variant = 10
    case variantSet = 11

    public var isConcrete: Bool {
        self != .unknown
    }
}
