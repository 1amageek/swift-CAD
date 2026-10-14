/// Witness-table access to the complete original pair and all UV families.
public protocol OriginalCoincidentConeRelationReading: Sendable {
    var original: OriginalCoincidentConeRelation { get }
    var isEmpty: Bool { get }
    var hasPositiveDimensionalSolutions: Bool { get }
    var hasPositiveDimensionalImage: Bool { get }
}
extension OriginalCoincidentConeRelation: OriginalCoincidentConeRelationReading {
    public var original: OriginalCoincidentConeRelation { self }
}
