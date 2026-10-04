import CADCore

/// Certifies position alone on the identical native UV chart of two stored surfaces.
public protocol GeometrySurfacePositionCertifying: Sendable {
    func certifyPosition(source: BSplineSurface3D, candidate: BSplineSurface3D,
        over parameters: SurfaceParameterBox, maximumPositionError: Double,
        limits: NativeSurfacePositionCertificationLimits,
        tolerance: ModelingTolerance) throws -> NativeSurfacePositionCertificate
}
