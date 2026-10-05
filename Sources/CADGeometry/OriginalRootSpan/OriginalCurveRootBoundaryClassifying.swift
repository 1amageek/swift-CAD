import CADCore

/// Exact original coefficient incidence and complete native span root isolation.
public protocol OriginalCurveRootBoundaryClassifying: Sendable {
    func roots<B: RationalAlgebraAdmitting>(of source: BSplineCurve3D, over trim: ScalarInterval,
        constraint: OriginalCurveIncidenceConstraint, maximumSpanCount: Int,
        maximumSubdivisionDepth: Int, tolerance: ModelingTolerance,
        usage: inout B) throws -> OriginalCurveRootClassification
    func roots<B: RationalAlgebraAdmitting>(of source: BSplineCurve3D,
        constraint: OriginalCurveIncidenceConstraint, maximumSpanCount: Int,
        maximumSubdivisionDepth: Int, tolerance: ModelingTolerance,
        usage: inout B) throws -> OriginalCurveRootClassification
}
