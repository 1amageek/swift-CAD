import CADCore

/// Certifies the original piecewise polynomial law and its outer end-span continuation.
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
