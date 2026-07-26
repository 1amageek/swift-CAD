import CADCore

struct DefaultCertifiedIntersectionReductionIntersector:
    CertifiedIntersectionReductionIntersecting
{
    private let surfaceSurfaceIntersector:
        any SurfaceSurfaceIntersecting
    private let candidateVerifier:
        any CertifiedIntersectionCandidateVerifying
    private let sectionCurveResolver:
        any CertifiedIntersectionSectionCurveResolving
    private let sectionComponentClassifier:
        any CertifiedReducedSectionComponentClassifying
    private let nodeCandidateResolver:
        any CertifiedIntersectionNodeCandidateResolving

    init(
        surfaceSurfaceIntersector:
            any SurfaceSurfaceIntersecting =
                DefaultSurfaceSurfaceIntersector(),
        candidateVerifier:
            any CertifiedIntersectionCandidateVerifying =
                DefaultCertifiedIntersectionCandidateVerifier(),
        sectionCurveResolver:
            any CertifiedIntersectionSectionCurveResolving =
                DefaultCertifiedIntersectionSectionCurveResolver(),
        sectionComponentClassifier:
            any CertifiedReducedSectionComponentClassifying =
                DefaultCertifiedReducedSectionComponentClassifier(),
        nodeCandidateResolver:
            any CertifiedIntersectionNodeCandidateResolving =
                DefaultCertifiedIntersectionNodeCandidateResolver()
    ) {
        self.surfaceSurfaceIntersector = surfaceSurfaceIntersector
        self.candidateVerifier = candidateVerifier
        self.sectionCurveResolver = sectionCurveResolver
        self.sectionComponentClassifier = sectionComponentClassifier
        self.nodeCandidateResolver = nodeCandidateResolver
    }

    func intersections(
        curve: CertifiedIntersectionCurve3D,
        targetSurface: Surface3D,
        reduction: CertifiedIntersectionReduction,
        options: CurveSurfaceIntersectionOptions,
        tolerance: ModelingTolerance,
        sectionCurveIntersector: any CurveSurfaceIntersecting
    ) throws -> [CurveSurfaceIntersection] {
        let sectionResults = try surfaceSurfaceIntersector.intersections(
            first: targetSurface,
            second: reduction.sectionSurface,
            options: surfaceOptions(
                from: options
            ),
            tolerance: tolerance
        )
        let sectionOptions = CurveSurfaceIntersectionOptions(
            maximumSubdivisionDepth: options.maximumSubdivisionDepth,
            maximumSubdivisionCells: options.maximumSubdivisionCells,
            maximumIterations: options.maximumIterations,
            maximumCandidateCount: options.maximumCandidateCount,
            maximumPolynomialDegree: options.maximumPolynomialDegree
        )
        var candidates: [CertifiedIntersectionCandidate] = []
        for sectionResult in sectionResults {
            switch sectionResult {
            case let .point(point):
                if let remainingResidual = try surfaceResidual(
                    at: point.point,
                    on: reduction.remainingSurface,
                    tolerance: tolerance
                ) {
                    candidates.append(CertifiedIntersectionCandidate(
                        point: point.point,
                        residual: max(point.residual, remainingResidual),
                        iterations: 0
                    ))
                }
            case let .curve(section):
                do {
                    let intersections = try sectionCurveIntersector.intersections(
                        curve: sectionCurveResolver.curve(for: section),
                        surface: reduction.remainingSurface,
                        options: sectionOptions,
                        tolerance: tolerance
                    )
                    candidates.append(contentsOf: intersections.map {
                        CertifiedIntersectionCandidate(
                            point: $0.point,
                            residual: $0.residual,
                            iterations: $0.iterations
                        )
                    })
                } catch let error as KernelError
                    where error.code == .nonDiscreteIntersection {
                    switch try sectionComponentClassifier.classification(
                        of: section,
                        relativeTo: curve,
                        targetSurface: targetSurface,
                        tolerance: tolerance
                    ) {
                    case .identical:
                        throw KernelError(
                            phase: .geometry,
                            code: .nonDiscreteIntersection,
                            residual: error.residual,
                            tolerance: tolerance,
                            message: "The target surface contains the queried certified intersection component."
                        )
                    case .distinct:
                        candidates.append(contentsOf: try nodeCandidateResolver
                            .candidates(
                                curve: curve,
                                targetSurface: targetSurface,
                                tolerance: tolerance
                            ))
                    }
                }
            case .coincident:
                throw KernelError(
                    phase: .geometry,
                    code: .nonDiscreteIntersection,
                    tolerance: tolerance,
                    message: "The target surface is continuously coincident with a certified curve source surface."
                )
            }
        }
        return try candidateVerifier.intersections(
            candidates: candidates,
            curve: curve,
            targetSurface: targetSurface,
            analyticTarget: try CertifiedAnalyticIntersectionTarget(
                surface: targetSurface,
                tolerance: tolerance
            ),
            options: options,
            tolerance: tolerance
        )
    }

    private func surfaceResidual(
        at point: Point3D,
        on surface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> Double? {
        do {
            let residual = try surface.parameterProjection(
                of: point,
                tolerance: tolerance
            ).residual
            return residual <= tolerance.distance ? residual : nil
        } catch let error as KernelError
            where error.code == .intersectionFailure
                && (error.residual ?? 0.0) > tolerance.distance {
            return nil
        }
    }

    private func surfaceOptions(
        from options: CurveSurfaceIntersectionOptions
    ) -> SurfaceSurfaceIntersectionOptions {
        SurfaceSurfaceIntersectionOptions(
            maximumSubdivisionDepth: options.maximumSubdivisionDepth,
            maximumSubdivisionCells: options.maximumSubdivisionCells,
            maximumIterations: options.maximumIterations,
            maximumSeedCount: options.maximumCandidateCount,
            maximumRootAttempts: options.maximumCandidateCount,
            maximumBoundarySubdivisionDepth: options.maximumSubdivisionDepth,
            maximumBoundarySubdivisionCells: min(
                options.maximumSubdivisionCells,
                1_048_576
            ),
            maximumPeriodicSeamAttempts: min(
                options.maximumCandidateCount,
                64
            ),
            maximumResidualCertificationDepth: options.maximumSubdivisionDepth,
            maximumResidualCertificationCells: min(
                options.maximumSubdivisionCells,
                1_048_576
            )
        )
    }

}
