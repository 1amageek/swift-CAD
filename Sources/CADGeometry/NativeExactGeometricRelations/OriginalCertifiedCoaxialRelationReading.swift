/// Requirements expose the immutable relation without existential specialization.
public protocol OriginalCertifiedCoaxialRelationReading: Sendable {
    var original: OriginalCertifiedCoaxialCurveSurfaceRelation { get }
    var isEmpty: Bool { get }
    var hasPositiveDimensionalSolutions: Bool { get }
    var hasPositiveDimensionalImage: Bool { get }
}

extension OriginalCertifiedCoaxialCurveSurfaceRelation: OriginalCertifiedCoaxialRelationReading {
    public var original: OriginalCertifiedCoaxialCurveSurfaceRelation { self }
}
