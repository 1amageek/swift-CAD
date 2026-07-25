import CADCore

struct DefaultConeCylinderConeIntersector: ConeCylinderConeIntersecting {
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
        curve: CertifiedConeCylinderIntersectionCurve,
        coneSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        let context = try context(
            curve: curve,
            coneSurface: coneSurface,
            tolerance: tolerance
        )
        return solver.supports(
            context: context,
            tolerance: tolerance
        )
    }

    func intersections(
        curve: CertifiedConeCylinderIntersectionCurve,
        coneSurface: Surface3D,
        options: CurveSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> [CurveSurfaceIntersection] {
        let context = try context(
            curve: curve,
            coneSurface: coneSurface,
            tolerance: tolerance
        )
        return try candidateVerifier.intersections(
            candidates: solver.candidates(
                context: context,
                options: options,
                tolerance: tolerance
            ),
            curve: .coneCylinder(curve),
            targetSurface: coneSurface,
            options: options,
            tolerance: tolerance
        )
    }

    private func context(
        curve: CertifiedConeCylinderIntersectionCurve,
        coneSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> ConeCylinderConeIntersectionContext {
        try ConeCylinderConeIntersectionContext(
            sourceConeSurface: curve.coneSurface,
            cylinderSurface: curve.cylinderSurface,
            targetConeSurface: coneSurface,
            tolerance: tolerance
        )
    }
}
