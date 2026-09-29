import CADCore

/// Evaluates a local contact section, not a complete fillet surface or solid.
public protocol RollingBallSectionEvaluating: Sendable {
    func section(atCurveParameter parameter: Double) throws -> RollingBallSection
    func contactCurve(
        on role: SurfaceIntersectionSurfaceRole,
        fromCurveParameter lower: Double,
        toCurveParameter upper: Double,
        options: CurveSurfaceCorrespondenceValidationOptions
    ) throws -> SurfaceLiftCurve3D
    func blendSurface(
        fromCurveParameter lower: Double,
        toCurveParameter upper: Double,
        options: CurveSurfaceCorrespondenceValidationOptions
    ) throws -> RollingBallBlendSurface3D
}
