import CADCore

struct DefaultCertifiedIntersectionCandidateVerifier:
    CertifiedIntersectionCandidateVerifying
{
    private let parameterResolver:
        any CertifiedIntersectionParameterResolving
    private let surfaceNormalResolver: any SurfaceNormalResolving

    init(
        parameterResolver:
            any CertifiedIntersectionParameterResolving =
                DefaultCertifiedIntersectionParameterResolver(),
        surfaceNormalResolver:
            any SurfaceNormalResolving = DefaultSurfaceNormalResolver()
    ) {
        self.parameterResolver = parameterResolver
        self.surfaceNormalResolver = surfaceNormalResolver
    }

    func intersections(
        candidates: [CertifiedIntersectionCandidate],
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
                let targetNormal = try surfaceNormalResolver.normal(
                    at: curveGeometry.position,
                    on: targetSurface,
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
                        message: "Certified curve-surface intersection failed final residual verification."
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
        let overlappingResidualBalls = 2.0 * tolerance.distance
        for intersection in sorted {
            if let index = result.firstIndex(where: { existing in
                (existing.point - intersection.point).length
                    <= overlappingResidualBalls
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
