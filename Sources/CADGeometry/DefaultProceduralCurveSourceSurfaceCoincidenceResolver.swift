import CADCore

struct DefaultProceduralCurveSourceSurfaceCoincidenceResolver:
    ProceduralCurveSourceSurfaceCoincidenceResolving
{
    private let analyticSurfaceEquivalenceResolver:
        any AnalyticSurfaceEquivalenceResolving

    init(
        analyticSurfaceEquivalenceResolver:
            any AnalyticSurfaceEquivalenceResolving =
                DefaultAnalyticSurfaceEquivalenceResolver()
    ) {
        self.analyticSurfaceEquivalenceResolver =
            analyticSurfaceEquivalenceResolver
    }

    func isSourceSurface(
        _ surface: Surface3D,
        of curve: Curve3D,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        switch curve {
        case let .implicit(implicitCurve):
            guard case let .bSpline(target) = surface else {
                return false
            }
            return target == implicitCurve.firstSurface
                || target == implicitCurve.secondSurface
        case let .surfaceLift(lift):
            return try analyticSurfaceEquivalenceResolver.areEquivalent(
                surface,
                lift.surface,
                tolerance: tolerance
            )
        case .line, .circle, .analytic, .bSpline, .certifiedIntersection:
            return false
        }
    }
}
