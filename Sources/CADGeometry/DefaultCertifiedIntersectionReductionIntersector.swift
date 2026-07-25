import CADCore

struct DefaultCertifiedIntersectionReductionIntersector:
    CertifiedIntersectionReductionIntersecting
{
    private let parameterResolver:
        any CertifiedIntersectionParameterResolving
    private let surfaceSurfaceIntersector:
        any SurfaceSurfaceIntersecting

    init(
        parameterResolver:
            any CertifiedIntersectionParameterResolving =
                DefaultCertifiedIntersectionParameterResolver(),
        surfaceSurfaceIntersector:
            any SurfaceSurfaceIntersecting =
                DefaultSurfaceSurfaceIntersector()
    ) {
        self.parameterResolver = parameterResolver
        self.surfaceSurfaceIntersector = surfaceSurfaceIntersector
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
        var candidates: [(point: Point3D, residual: Double, iterations: Int)] = []
        for sectionResult in sectionResults {
            switch sectionResult {
            case let .point(point):
                if let remainingResidual = try surfaceResidual(
                    at: point.point,
                    on: reduction.remainingSurface,
                    tolerance: tolerance
                ) {
                    candidates.append((
                        point.point,
                        max(point.residual, remainingResidual),
                        0
                    ))
                }
            case let .curve(section):
                do {
                    let intersections = try sectionCurveIntersector.intersections(
                        curve: section.curve,
                        surface: reduction.remainingSurface,
                        options: sectionOptions,
                        tolerance: tolerance
                    )
                    candidates.append(contentsOf: intersections.map {
                        ($0.point, $0.residual, $0.iterations)
                    })
                } catch let error as KernelError
                    where error.code == .nonDiscreteIntersection {
                    // FIXME(INCOMPLETE_IMPLEMENTATION): A reduced target section that is
                    // continuously coincident with the remaining source surface is not
                    // yet matched to one certified component. The production certified
                    // curve reduction reaches this catch, and it must not report
                    // non-discrete success until component identity is proved.
                    throw KernelError(
                        phase: .geometry,
                        code: .unsupportedCapability,
                        residual: error.residual,
                        tolerance: tolerance,
                        message: "A continuously coincident reduced section requires certified component identity."
                    )
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
        return try verifiedIntersections(
            candidates: candidates,
            curve: curve,
            targetSurface: targetSurface,
            options: options,
            tolerance: tolerance
        )
    }

    private func verifiedIntersections(
        candidates: [(point: Point3D, residual: Double, iterations: Int)],
        curve: CertifiedIntersectionCurve3D,
        targetSurface: Surface3D,
        options: CurveSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> [CurveSurfaceIntersection] {
        var intersections: [CurveSurfaceIntersection] = []
        for candidate in candidates {
            let parameters = try parameterResolver.normalizedParameters(
                of: candidate.point,
                on: curve,
                restrictedTo: options.curveRange,
                tolerance: tolerance
            )
            for parameter in parameters {
                let curveGeometry = try Curve3D.certifiedIntersection(curve)
                    .differentialGeometry(
                        at: parameter,
                        tolerance: tolerance
                    )
                let targetProjection = try targetSurface.parameterProjection(
                    of: curveGeometry.position,
                    tolerance: tolerance
                )
                guard contains(
                    targetProjection.u,
                    range: options.surfaceURange
                ), contains(
                    targetProjection.v,
                    range: options.surfaceVRange
                ) else {
                    continue
                }
                let targetPoint = try targetSurface.point(
                    u: targetProjection.u,
                    v: targetProjection.v,
                    tolerance: tolerance
                )
                let targetNormal = try targetSurface.normal(
                    u: targetProjection.u,
                    v: targetProjection.v,
                    tolerance: tolerance
                )
                let residual = max(
                    candidate.residual,
                    max(
                        targetProjection.residual,
                        max(
                            (candidate.point - curveGeometry.position).length,
                            (targetPoint - curveGeometry.position).length
                        )
                    )
                )
                guard residual <= tolerance.distance else {
                    throw KernelError(
                        phase: .geometry,
                        code: .intersectionFailure,
                        residual: residual,
                        tolerance: tolerance,
                        message: "Certified curve-surface reduction failed final residual verification."
                    )
                }
                intersections.append(try CurveSurfaceIntersection(
                    point: curveGeometry.position,
                    curveParameter: parameter,
                    surfaceU: targetProjection.u,
                    surfaceV: targetProjection.v,
                    kind: abs(curveGeometry.tangent.dot(targetNormal))
                        <= tolerance.angle ? .tangent : .transverse,
                    residual: residual,
                    iterations: candidate.iterations
                ))
            }
        }
        return deduplicated(intersections, tolerance: tolerance)
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

    private func contains(
        _ value: Double,
        range: ScalarInterval?
    ) -> Bool {
        range?.contains(value) ?? true
    }

    private func deduplicated(
        _ intersections: [CurveSurfaceIntersection],
        tolerance: ModelingTolerance
    ) -> [CurveSurfaceIntersection] {
        let sorted = intersections.sorted { lhs, rhs in
            if lhs.curveParameter != rhs.curveParameter {
                return lhs.curveParameter < rhs.curveParameter
            }
            if lhs.surfaceU != rhs.surfaceU {
                return lhs.surfaceU < rhs.surfaceU
            }
            return lhs.surfaceV < rhs.surfaceV
        }
        var result: [CurveSurfaceIntersection] = []
        for intersection in sorted {
            if let index = result.firstIndex(where: { existing in
                (existing.point - intersection.point).length
                    <= tolerance.distance
                    && abs(
                        existing.curveParameter
                            - intersection.curveParameter
                    ) <= max(tolerance.distance, tolerance.angle)
            }) {
                if intersection.residual < result[index].residual {
                    result[index] = intersection
                }
            } else {
                result.append(intersection)
            }
        }
        return result
    }
}
