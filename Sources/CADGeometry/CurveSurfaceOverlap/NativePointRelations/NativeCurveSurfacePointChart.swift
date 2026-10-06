import CADCore

/// Immutable law and complete closed coverage of one original span product.
package struct NativeCurveSurfacePointChart: Sendable {
    package let curve: OriginalRationalCurvePolynomial
    package let surface: OriginalRationalSurfacePolynomial
    package let decomposition: OriginalRationalIntersectionDecomposition
}
