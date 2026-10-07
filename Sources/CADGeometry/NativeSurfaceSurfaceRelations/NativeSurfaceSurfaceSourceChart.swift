import CADCore

/// Source-issued closed chart binding, independent of any local solution proof.
package struct NativeSurfaceSurfaceSourceChart: Sendable {
    package let firstOwner: PreparedBSplineSurfaceDifferentialEncloser.OriginalNativeSpan
    package let secondOwner: PreparedBSplineSurfaceDifferentialEncloser.OriginalNativeSpan
    package let first: OriginalRationalSurfacePolynomial
    package let second: OriginalRationalSurfacePolynomial
    package let system: OriginalRationalIntersectionSystem
    package let nativeDomains: [OriginalRationalParameterDomain]
}
