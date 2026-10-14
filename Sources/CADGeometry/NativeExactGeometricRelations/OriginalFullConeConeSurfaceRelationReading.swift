/// Witness-table access to the complete original pair and all UV families.
public protocol OriginalFullConeConeSurfaceRelationReading: Sendable {
    var original: OriginalFullConeConeSurfaceRelation { get }
    var isEmpty: Bool { get }
    var hasPositiveDimensionalSolutions: Bool { get }
    var hasPositiveDimensionalImage: Bool { get }
}
extension OriginalFullConeConeSurfaceRelation: OriginalFullConeConeSurfaceRelationReading {
    public var original: OriginalFullConeConeSurfaceRelation { self }
}
