/// Actual implicit source authority and complete issued geometry remain readable on Embedded.
public protocol OriginalImplicitCurveRelationReading: Sendable {
    var original: OriginalImplicitCurveSnapshot { get }
    /// Complete authority for every stored original cell, including an empty requested intersection.
    var finiteCoverage: OriginalFiniteImplicitCurveGraphCoverage { get }
    /// Evidence for only the first stored cell.
    var firstEvidence: OriginalImplicitCurveGraphEvidence { get }
    /// Reduction for only the first stored cell.
    var firstReduction: OriginalImplicitCurveGraphReduction { get }
    @available(*, deprecated, renamed: "firstEvidence", message: "This is only the first stored cell; finiteCoverage owns the whole family.")
    var evidence: OriginalImplicitCurveGraphEvidence { get }
    @available(*, deprecated, renamed: "firstReduction", message: "This is only the first stored cell; finiteCoverage owns the whole family.")
    var reduction: OriginalImplicitCurveGraphReduction { get }
    var geometry: any OriginalIssuedGeometricRelationReading { get }
    var isEmpty: Bool { get }
    var hasPositiveDimensionalSolutions: Bool { get }
    var hasPositiveDimensionalImage: Bool { get }
}
