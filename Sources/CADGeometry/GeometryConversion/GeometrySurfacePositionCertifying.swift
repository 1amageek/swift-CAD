import CADCore

/// Certifies position alone on the identical native UV chart of two stored surfaces.
/// Finite periodic charts retain their original repeated homogeneous law and closed
/// fundamental covers. No clipping to a selected representative interval is applied.
/// Native open axes must contain the complete requested rectangle. Periodic
/// discontinuity, unresolved original derivative coverage and resource exhaustion
/// fail explicitly rather than authorizing an incomplete position guarantee.
public protocol GeometrySurfacePositionCertifying: Sendable {
    func certifyPosition(source: BSplineSurface3D, candidate: BSplineSurface3D,
        over parameters: SurfaceParameterBox, maximumPositionError: Double,
        limits: NativeSurfacePositionCertificationLimits,
        tolerance: ModelingTolerance) throws -> NativeSurfacePositionCertificate
}
