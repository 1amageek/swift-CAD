import CADCore

protocol AnalyticSurfaceImplicitDifferentialEvaluating: Sendable {
    func differential(
        at point: Point3D,
        on surface: CanonicalAnalyticSurface
    ) throws -> AnalyticSurfaceImplicitDifferential

    func curveSecondDerivative(
        geometry: Curve3D.DifferentialGeometry,
        implicitGradient: Vector3D,
        surface: CanonicalAnalyticSurface
    ) throws -> Double
}
