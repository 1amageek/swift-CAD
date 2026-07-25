import CADCore

struct DefaultCertifiedReducedSectionIntersectionBoundResolver:
    CertifiedReducedSectionIntersectionBoundResolving
{
    func isolatedIntersectionUpperBound(
        curve: CertifiedIntersectionCurve3D,
        targetSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> Int {
        try curveDegree(curve) * targetDegree(
            targetSurface,
            tolerance: tolerance
        )
    }

    private func curveDegree(
        _ curve: CertifiedIntersectionCurve3D
    ) -> Int {
        switch curve {
        case .sphereCone, .coneCone, .coneCylinder:
            return 4
        case .coneTorus:
            return 8
        case .parallelTorusTorus:
            return 16
        }
    }

    private func targetDegree(
        _ surface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> Int {
        switch CanonicalAnalyticSurface(surface) {
        case .plane:
            return 1
        case .sphere, .cylinder, .cone:
            return 2
        case .torus:
            return 4
        case .unsupported:
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                tolerance: tolerance,
                message: "Reduced-section component classification requires a target surface with a certified algebraic degree."
            )
        }
    }
}
