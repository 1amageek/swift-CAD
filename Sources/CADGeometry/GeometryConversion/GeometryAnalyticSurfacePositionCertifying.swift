import CADCore

/// Certifies a candidate against the original analytic surface's native UV law.
///
/// Plane, cylinder, cone, sphere and torus sources retain their complete requested
/// native chart. The certificate covers position alone; singular source parameters
/// do not imply valid tangents or curvatures. Candidates retain their actual native
/// knots and positive weights. Unsupported sources, missing domain coverage,
/// unmet error allowances and exhausted caller budgets fail explicitly.
public protocol GeometryAnalyticSurfacePositionCertifying: Sendable {
    func certifyPosition(source: Surface3D, candidate: BSplineSurface3D,
        over parameters: SurfaceParameterBox, maximumPositionError: Double,
        limits: NativeSurfacePositionCertificationLimits,
        tolerance: ModelingTolerance) throws -> NativeSurfacePositionCertificate
}
