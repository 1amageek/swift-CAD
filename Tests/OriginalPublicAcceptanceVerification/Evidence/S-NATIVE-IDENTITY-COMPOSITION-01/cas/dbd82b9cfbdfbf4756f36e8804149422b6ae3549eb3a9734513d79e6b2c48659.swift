import CADGeometry

/// Stores the outward-rounded Bernstein coefficients of a surface-flux Green
/// primitive over the normalized parameter domain of one Bezier surface.
struct CertifiedPolynomialSurfaceFluxPrimitive: Sendable, Hashable {
    typealias Interval = TrimmedAnalyticSurfaceVolumeEvaluator.Interval

    let coefficients: [[Interval]]
    let uDomain: ParameterDomain
    let vDomain: ParameterDomain
}
