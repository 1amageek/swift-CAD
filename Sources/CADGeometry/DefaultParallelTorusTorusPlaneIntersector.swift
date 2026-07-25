import CADCore
import Foundation

struct DefaultParallelTorusTorusPlaneIntersector:
    ParallelTorusTorusPlaneIntersecting
{
    private let polynomialBuilder:
        any ParallelTorusTorusPlanePolynomialBuilding

    init(
        polynomialBuilder:
            any ParallelTorusTorusPlanePolynomialBuilding =
                DefaultParallelTorusTorusPlanePolynomialBuilder()
    ) {
        self.polynomialBuilder = polynomialBuilder
    }

    func intersections(
        curve: CertifiedParallelTorusTorusIntersectionCurve,
        planeSurface: Surface3D,
        options: CurveSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> [CurveSurfaceIntersection] {
        guard case let .plane(plane) = CanonicalAnalyticSurface(planeSurface) else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Parallel torus-torus plane intersection requires an exact analytic plane."
            )
        }
        let context = try curve.planeIntersectionContext(
            tolerance: tolerance
        )
        let normal = try plane.normal.normalized(
            tolerance: tolerance.distance
        )
        let coefficients = polynomialBuilder.coefficients(
            context: context,
            planeOrigin: plane.origin,
            planeNormal: normal
        )
        guard coefficients.allSatisfy(\.isFinite) else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                tolerance: tolerance,
                message: "Parallel torus-torus plane elimination produced non-finite coefficients."
            )
        }
        let coefficientScale = coefficients.map(abs).max() ?? 0.0
        let zeroThreshold = pow(
            max(context.characteristicLength, 1.0),
            4.0
        ) * Double.ulpOfOne * 4_096.0
        guard zeroThreshold.isFinite else {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                tolerance: tolerance,
                message: "Parallel torus-torus plane elimination exceeded the finite arithmetic envelope."
            )
        }
        guard coefficientScale > zeroThreshold else {
            if try isContinuouslyCoincident(
                curve: curve,
                planeOrigin: plane.origin,
                planeNormal: normal,
                tolerance: tolerance
            ) {
                throw KernelError(
                    phase: .geometry,
                    code: .nonDiscreteIntersection,
                    tolerance: tolerance,
                    message: "A parallel torus-torus component lies continuously in the target plane."
                )
            }
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                tolerance: tolerance,
                message: "Parallel torus-torus plane elimination produced an indeterminate zero polynomial."
            )
        }
        let normalizedCoefficients = coefficients.map {
            $0 / coefficientScale
        }
        let polynomialDegree = effectiveDegree(
            normalizedCoefficients
        )
        guard polynomialDegree <= options.maximumPolynomialDegree else {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                tolerance: tolerance,
                message: "Parallel torus-torus plane elimination exceeded the requested polynomial-degree limit."
            )
        }
        let solver = try RealPolynomialRootSolver(
            rootTolerance: max(
                tolerance.angle * 0.001,
                Double.ulpOfOne * 64.0
            ),
            residualTolerance: max(
                tolerance.angle * 0.001,
                Double.ulpOfOne * 64.0
            ),
            coefficientTolerance: Double.ulpOfOne * 128.0
        )
        var angles = try solver.realRoots(
            coefficients: normalizedCoefficients
        ).map {
            normalizedAngle(2.0 * atan($0))
        }
        if try isVerifiedAngle(
            Double.pi,
            curve: curve,
            planeOrigin: plane.origin,
            planeNormal: normal,
            tolerance: tolerance
        ) {
            angles.append(Double.pi)
        }
        angles = deduplicatedAngles(
            angles,
            tolerance: tolerance.angle
        )
        guard angles.count <= options.maximumCandidateCount else {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                tolerance: tolerance,
                message: "Parallel torus-torus plane intersection exceeded the requested candidate limit."
            )
        }

        var intersections: [CurveSurfaceIntersection] = []
        var candidateCount = 0
        for angle in angles {
            let parameters = try curve.normalizedFractionCandidates(
                forPrimaryTubeAngle: angle,
                tolerance: tolerance
            )
            for parameter in parameters {
                candidateCount += 1
                guard candidateCount <= options.maximumCandidateCount else {
                    throw KernelError(
                        phase: .geometry,
                        code: .resourceLimitExceeded,
                        tolerance: tolerance,
                        message: "Parallel torus-torus plane parameter recovery exceeded the requested candidate limit."
                    )
                }
                guard contains(
                    parameter,
                    range: options.curveRange
                ), let refinement = try refinedParameter(
                    parameter,
                    curve: curve,
                    planeOrigin: plane.origin,
                    planeNormal: normal,
                    options: options,
                    tolerance: tolerance
                ) else {
                    continue
                }
                let geometry = try Curve3D.certifiedIntersection(
                    .parallelTorusTorus(curve)
                ).differentialGeometry(
                    at: refinement.parameter,
                    tolerance: tolerance
                )
                let projection = try planeSurface.parameterProjection(
                    of: geometry.position,
                    tolerance: tolerance
                )
                guard projection.residual <= tolerance.distance,
                      contains(
                          projection.u,
                          range: options.surfaceURange
                      ), contains(
                          projection.v,
                          range: options.surfaceVRange
                      ) else {
                    continue
                }
                let planePoint = try planeSurface.point(
                    u: projection.u,
                    v: projection.v,
                    tolerance: tolerance
                )
                let residual = max(
                    projection.residual,
                    (planePoint - geometry.position).length
                )
                guard residual <= tolerance.distance else {
                    throw KernelError(
                        phase: .geometry,
                        code: .intersectionFailure,
                        residual: residual,
                        tolerance: tolerance,
                        message: "Parallel torus-torus plane intersection failed final residual verification."
                    )
                }
                intersections.append(try CurveSurfaceIntersection(
                    point: geometry.position,
                    curveParameter: refinement.parameter,
                    surfaceU: projection.u,
                    surfaceV: projection.v,
                    kind: abs(geometry.tangent.dot(normal))
                        <= tolerance.angle ? .tangent : .transverse,
                    residual: residual,
                    iterations: refinement.iterations
                ))
            }
        }
        return deduplicated(intersections, tolerance: tolerance)
    }

    private func refinedParameter(
        _ initial: Double,
        curve: CertifiedParallelTorusTorusIntersectionCurve,
        planeOrigin: Point3D,
        planeNormal: Vector3D,
        options: CurveSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> (parameter: Double, iterations: Int)? {
        let piece: ClosedRange<Double>
        if curve.componentKind == .nearNodalClosedLoop {
            piece = initial <= 0.5 ? 0.0...0.5 : 0.5...1.0
        } else {
            piece = 0.0...1.0
        }
        let lower = max(
            piece.lowerBound,
            options.curveRange?.lower ?? 0.0
        )
        let upper = min(
            piece.upperBound,
            options.curveRange?.upper ?? 1.0
        )
        guard lower <= upper,
              initial >= lower - tolerance.relative,
              initial <= upper + tolerance.relative else {
            return nil
        }
        var parameter = min(max(initial, lower), upper)
        var iterations = 0
        for iteration in 0..<options.maximumIterations {
            iterations = iteration + 1
            let geometry = try curve.differential(
                atNormalizedFraction: parameter,
                tolerance: tolerance
            )
            let value = (geometry.position - planeOrigin).dot(planeNormal)
            if abs(value) <= tolerance.distance * 0.125 {
                break
            }
            let first = geometry.firstDerivative.dot(planeNormal)
            let step: Double
            if abs(first) > tolerance.distance * 0.001 {
                step = value / first
            } else {
                let second = geometry.secondDerivative.dot(planeNormal)
                guard abs(second) > tolerance.distance * 0.001 else {
                    break
                }
                step = first / second
            }
            guard step.isFinite else { break }
            let candidate = min(max(parameter - step, lower), upper)
            if abs(candidate - parameter) <= Double.ulpOfOne
                * max(abs(parameter), 1.0) * 128.0 {
                parameter = candidate
                break
            }
            parameter = candidate
        }
        let point = try curve.point(
            atNormalizedFraction: parameter,
            tolerance: tolerance
        )
        guard abs((point - planeOrigin).dot(planeNormal))
            <= tolerance.distance else {
            return nil
        }
        return (parameter, iterations)
    }

    private func isContinuouslyCoincident(
        curve: CertifiedParallelTorusTorusIntersectionCurve,
        planeOrigin: Point3D,
        planeNormal: Vector3D,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        for index in 0...16 {
            let point = try curve.point(
                atNormalizedFraction: Double(index) / 16.0,
                tolerance: tolerance
            )
            if abs((point - planeOrigin).dot(planeNormal))
                > tolerance.distance {
                return false
            }
        }
        return true
    }

    private func isVerifiedAngle(
        _ angle: Double,
        curve: CertifiedParallelTorusTorusIntersectionCurve,
        planeOrigin: Point3D,
        planeNormal: Vector3D,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        let parameters = try curve.normalizedFractionCandidates(
            forPrimaryTubeAngle: angle,
            tolerance: tolerance
        )
        for parameter in parameters {
            let point = try curve.point(
                atNormalizedFraction: parameter,
                tolerance: tolerance
            )
            if abs((point - planeOrigin).dot(planeNormal))
                <= tolerance.distance {
                return true
            }
        }
        return false
    }

    private func effectiveDegree(_ coefficients: [Double]) -> Int {
        var degree = max(coefficients.count - 1, 0)
        while degree > 0,
              abs(coefficients[degree]) <= Double.ulpOfOne * 128.0 {
            degree -= 1
        }
        return degree
    }

    private func normalizedAngle(_ angle: Double) -> Double {
        let period = 2.0 * Double.pi
        let remainder = angle.truncatingRemainder(dividingBy: period)
        return remainder >= 0.0 ? remainder : remainder + period
    }

    private func deduplicatedAngles(
        _ angles: [Double],
        tolerance: Double
    ) -> [Double] {
        var result: [Double] = []
        for angle in angles.sorted() {
            if result.contains(where: {
                angularDistance($0, angle) <= tolerance
            }) == false {
                result.append(angle)
            }
        }
        return result
    }

    private func angularDistance(
        _ first: Double,
        _ second: Double
    ) -> Double {
        let period = 2.0 * Double.pi
        let difference = abs(first - second)
            .truncatingRemainder(dividingBy: period)
        return min(difference, period - difference)
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
        let sorted = intersections.sorted {
            $0.curveParameter < $1.curveParameter
        }
        var result: [CurveSurfaceIntersection] = []
        for intersection in sorted {
            if let index = result.firstIndex(where: {
                ($0.point - intersection.point).length
                    <= tolerance.distance
                    && abs(
                        $0.curveParameter
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
