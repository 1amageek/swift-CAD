/// Witness-table access to the complete original pair and all UV families.
public protocol OriginalBoundedSphereConeSurfaceRelationReading: Sendable {
    var original: OriginalBoundedSphereConeSurfaceRelation { get }
    var isEmpty: Bool { get }
    var hasPositiveDimensionalSolutions: Bool { get }
    var hasPositiveDimensionalImage: Bool { get }
}
extension OriginalBoundedSphereConeSurfaceRelation: OriginalBoundedSphereConeSurfaceRelationReading {
    public var original: OriginalBoundedSphereConeSurfaceRelation { self }
}
