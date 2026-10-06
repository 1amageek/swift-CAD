import CADCore

/// Immutable source binding with an optional proved local partition.
package struct NativeCurveSurfacePointChart: Sendable {
    package let curveOwner: OriginalNativeCurveChartCover.OwnedSpan
    package let surfaceOwner: PreparedBSplineSurfaceDifferentialEncloser.OriginalNativeSpan
    package var curve: OriginalRationalCurvePolynomial { curveOwner.law }
    package let surface: OriginalRationalSurfacePolynomial
    package let system: OriginalRationalIntersectionSystem
    package let nativeDomains: [OriginalRationalParameterDomain]
    package let decomposition: OriginalRationalIntersectionDecomposition?
}
