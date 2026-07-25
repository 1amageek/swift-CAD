import CADCore

struct DefaultCertifiedIntersectionCoincidenceResolver:
    CertifiedIntersectionCoincidenceResolving
{
    private let surfaceEquivalenceResolver:
        any AnalyticSurfaceEquivalenceResolving

    init(
        surfaceEquivalenceResolver:
            any AnalyticSurfaceEquivalenceResolving =
                DefaultAnalyticSurfaceEquivalenceResolver()
    ) {
        self.surfaceEquivalenceResolver = surfaceEquivalenceResolver
    }

    func isSourceSurface(
        _ surface: Surface3D,
        of curve: CertifiedIntersectionCurve3D,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        switch curve {
        case let .sphereCone(curve):
            return try matches(
                surface,
                either: curve.sphereSurface,
                or: curve.coneSurface,
                tolerance: tolerance
            )
        case let .coneCone(curve):
            return try matches(
                surface,
                either: curve.referenceSurface,
                or: curve.parameterizedSurface,
                tolerance: tolerance
            )
        case let .coneCylinder(curve):
            return try matches(
                surface,
                either: curve.coneSurface,
                or: curve.cylinderSurface,
                tolerance: tolerance
            )
        case let .coneTorus(curve):
            return try matches(
                surface,
                either: curve.coneSurface,
                or: curve.torusSurface,
                tolerance: tolerance
            )
        case let .parallelTorusTorus(curve):
            return try matches(
                surface,
                either: curve.primarySurface,
                or: curve.secondarySurface,
                tolerance: tolerance
            )
        }
    }

    private func matches(
        _ surface: Surface3D,
        either first: Surface3D,
        or second: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        if try surfaceEquivalenceResolver.areEquivalent(
            surface,
            first,
            tolerance: tolerance
        ) {
            return true
        }
        return try surfaceEquivalenceResolver.areEquivalent(
            surface,
            second,
            tolerance: tolerance
        )
    }
}
