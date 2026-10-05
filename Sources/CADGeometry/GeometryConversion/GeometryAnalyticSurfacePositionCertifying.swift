import CADCore

/// Certifies a candidate against the original analytic surface's native UV law.
public protocol GeometryAnalyticSurfacePositionCertifying: Sendable {
    func certifyPosition(source: Surface3D, candidate: BSplineSurface3D,
        over parameters: SurfaceParameterBox, maximumPositionError: Double,
        limits: NativeSurfacePositionCertificationLimits,
        tolerance: ModelingTolerance) throws -> NativeSurfacePositionCertificate
}
