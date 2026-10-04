import CADCore

/// Certifies the unique original polynomial law beyond a single Bezier support.
public protocol GeometryPolynomialSurfaceContinuationPositionCertifying: Sendable {
    func prepareContinuationRequest(source: BSplineSurface3D,
        over parameters: SurfaceParameterBox, maximumPositionError: Double,
        limits: NativeSurfacePositionCertificationLimits,
        tolerance: ModelingTolerance) throws -> PreparedPolynomialSurfaceContinuationPositionRequest

    func certifyContinuationPosition(preparedRequest: PreparedPolynomialSurfaceContinuationPositionRequest,
        candidate: BSplineSurface3D) throws -> NativeSurfacePositionCertificate

    func certifyContinuationPosition(source: BSplineSurface3D, candidate: BSplineSurface3D,
        over parameters: SurfaceParameterBox, maximumPositionError: Double,
        limits: NativeSurfacePositionCertificationLimits,
        tolerance: ModelingTolerance) throws -> NativeSurfacePositionCertificate
}
