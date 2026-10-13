/// Witness-table operations expose complete original primitive SSI families.
public protocol OriginalCoaxialSurfaceRelationReading: Sendable {
    var original: OriginalCoaxialSurfaceSurfaceRelation { get }
    var isEmpty: Bool { get }
    var hasPositiveDimensionalSolutions: Bool { get }
    var hasPositiveDimensionalImage: Bool { get }
}
extension OriginalCoaxialSurfaceSurfaceRelation: OriginalCoaxialSurfaceRelationReading {
    public var original: OriginalCoaxialSurfaceSurfaceRelation { self }
}
