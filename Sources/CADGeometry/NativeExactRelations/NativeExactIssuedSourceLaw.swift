import CADCore

/// Keeps the family-issued original law alive throughout relation construction.
enum NativeExactIssuedSourceLaw: Sendable {
    typealias Field = ExactAlgebraicScalarDomain<ExactRationalScalarDomain>
    case curve(OriginalRationalChartReceipt<BSplineCurve3D, OriginalBSplineChartSelection, Field>)
    case surface(OriginalRationalChartReceipt<BSplineSurface3D, OriginalBSplineChartSelection, Field>)
}
