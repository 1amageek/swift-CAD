/// Witness-table access to the complete original pair and all UV families.
public protocol OriginalApexSphereConeSurfaceRelationReading: Sendable {
    var original: OriginalApexSphereConeSurfaceRelation { get }
    var isEmpty: Bool { get }
    var hasPositiveDimensionalSolutions: Bool { get }
    var hasPositiveDimensionalImage: Bool { get }
}
extension OriginalApexSphereConeSurfaceRelation: OriginalApexSphereConeSurfaceRelationReading {
    public var original: OriginalApexSphereConeSurfaceRelation { self }
}
