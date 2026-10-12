/// Actual implicit source authority and complete issued geometry remain readable on Embedded.
public protocol OriginalImplicitCurveRelationReading: Sendable {
    var original: OriginalImplicitCurveSnapshot { get }
    var evidence: OriginalImplicitCurveGraphEvidence { get }
    var reduction: OriginalImplicitCurveGraphReduction { get }
    var geometry: any OriginalIssuedGeometricRelationReading { get }
    var isEmpty: Bool { get }
    var hasPositiveDimensionalSolutions: Bool { get }
    var hasPositiveDimensionalImage: Bool { get }
}
