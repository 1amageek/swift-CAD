import CADCore

/// Complete original native-span incidence coverage with isolated and continuous strata.
public struct OriginalCurveRootClassification: Sendable {
    public let source: BSplineCurve3D
    public let constraint: OriginalCurveIncidenceConstraint
    public let isolated: [OriginalCurveRootBoundary]
    public let coincidentSpans: [ScalarInterval]
    public let certificationTolerance: ModelingTolerance
}
