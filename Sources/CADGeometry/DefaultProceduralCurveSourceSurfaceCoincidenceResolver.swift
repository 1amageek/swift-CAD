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
        if try curve.otherIntersectionSupportSurface(
            on: surface,
            tolerance: tolerance
        ) != nil {
            return true
        }
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
        case let .rigidImage(image):
            return try isTransformedSourceSurface(
                surface,
                sourceCurve: image.source,
                transform: image.transform,
                tolerance: tolerance
            )
        case .line, .circle, .analytic, .bSpline, .certifiedIntersection,
             .affineImage:
            return false
        }
    }

    private func isTransformedSourceSurface(
        _ surface: Surface3D,
        sourceCurve: Curve3D,
        transform: RigidTransform3D,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        let sourceSurfaces: [Surface3D]
        switch sourceCurve {
        case let .implicit(curve):
            sourceSurfaces = [
                .bSpline(curve.firstSurface),
                .bSpline(curve.secondSurface),
            ]
        case let .surfaceLift(lift):
            sourceSurfaces = [lift.surface]
        case let .rigidImage(image):
            return try isTransformedSourceSurface(
                surface,
                sourceCurve: image.source,
                transform: transform.composed(after: image.transform),
                tolerance: tolerance
            )
        case .line, .circle, .analytic, .bSpline, .certifiedIntersection,
             .affineImage:
            return false
        }
        for sourceSurface in sourceSurfaces {
            let image = try transform.applying(
                to: sourceSurface,
                tolerance: tolerance
            )
            if try analyticSurfaceEquivalenceResolver.areEquivalent(
                surface,
                image,
                tolerance: tolerance
            ) {
                return true
            }
        }
        return false
    }
}
