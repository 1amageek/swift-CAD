/// Witness-table access to the complete original pair and all UV families.
public protocol OriginalFullSphereConeSurfaceRelationReading: Sendable {
    var original: OriginalFullSphereConeSurfaceRelation { get }
    var isEmpty: Bool { get }
    var hasPositiveDimensionalSolutions: Bool { get }
    var hasPositiveDimensionalImage: Bool { get }
}
extension OriginalFullSphereConeSurfaceRelation: OriginalFullSphereConeSurfaceRelationReading {
    public var original: OriginalFullSphereConeSurfaceRelation { self }
}
