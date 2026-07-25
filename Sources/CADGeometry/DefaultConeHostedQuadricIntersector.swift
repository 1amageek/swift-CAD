import CADCore

struct DefaultConeHostedQuadricIntersector:
    ConeHostedQuadricIntersecting
{
    private struct Surfaces {
        let hostCone: Surface3D
        let sourceQuadric: Surface3D
    }

    private let solver: any HeightQuadraticTripleSolving
    private let candidateVerifier:
        any CertifiedIntersectionCandidateVerifying

    init(
        solver:
            any HeightQuadraticTripleSolving =
                DefaultHeightQuadraticTripleSolver(),
        candidateVerifier:
            any CertifiedIntersectionCandidateVerifying =
                DefaultCertifiedIntersectionCandidateVerifier()
    ) {
        self.solver = solver
        self.candidateVerifier = candidateVerifier
    }

    func supports(
        curve: CertifiedIntersectionCurve3D,
        targetSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        guard let context = try context(
            curve: curve,
            targetSurface: targetSurface,
            tolerance: tolerance
        ) else {
            return false
        }
        return solver.supports(
            context: context,
            tolerance: tolerance
        )
    }

    func intersections(
        curve: CertifiedIntersectionCurve3D,
        targetSurface: Surface3D,
        options: CurveSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> [CurveSurfaceIntersection] {
        guard let context = try context(
            curve: curve,
            targetSurface: targetSurface,
            tolerance: tolerance
        ) else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Cone-hosted quadric elimination received an unsupported curve or target."
            )
        }
        return try candidateVerifier.intersections(
            candidates: solver.candidates(
                context: context,
                options: options,
                tolerance: tolerance
            ),
            curve: curve,
            targetSurface: targetSurface,
            options: options,
            tolerance: tolerance
        )
    }

    private func context(
        curve: CertifiedIntersectionCurve3D,
        targetSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> ConeHostedQuadricIntersectionContext? {
        guard isSupportedTarget(targetSurface),
              let surfaces = sourceSurfaces(curve) else {
            return nil
        }
        return try ConeHostedQuadricIntersectionContext(
            hostConeSurface: surfaces.hostCone,
            sourceSurface: surfaces.sourceQuadric,
            targetSurface: targetSurface,
            tolerance: tolerance
        )
    }

    private func sourceSurfaces(
        _ curve: CertifiedIntersectionCurve3D
    ) -> Surfaces? {
        switch curve {
        case let .sphereCone(curve):
            return Surfaces(
                hostCone: curve.coneSurface,
                sourceQuadric: curve.sphereSurface
            )
        case let .coneCone(curve):
            return Surfaces(
                hostCone: curve.parameterizedSurface,
                sourceQuadric: curve.referenceSurface
            )
        case .coneCylinder, .coneTorus, .parallelTorusTorus:
            return nil
        }
    }

    private func isSupportedTarget(_ surface: Surface3D) -> Bool {
        switch CanonicalAnalyticSurface(surface) {
        case .sphere, .cylinder, .cone:
            return true
        case .plane, .torus, .unsupported:
            return false
        }
    }
}
