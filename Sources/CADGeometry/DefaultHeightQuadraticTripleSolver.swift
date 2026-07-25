import CADCore
import Foundation

struct DefaultHeightQuadraticTripleSolver:
    HeightQuadraticTripleSolving
{
    private let polynomialBuilder:
        any HeightQuadraticResultantPolynomialBuilding

    init(
        polynomialBuilder:
            any HeightQuadraticResultantPolynomialBuilding =
                DefaultHeightQuadraticResultantPolynomialBuilder()
    ) {
        self.polynomialBuilder = polynomialBuilder
    }

    func supports(
        context: any HeightQuadraticIntersectionContext,
        tolerance: ModelingTolerance
    ) -> Bool {
        let polynomial = polynomial(context: context)
        guard polynomial.coefficients.allSatisfy(\.isFinite),
              polynomial.forwardErrorScale.isFinite else {
            return false
        }
        let coefficientScale =
            polynomial.coefficients.map(abs).max() ?? 0.0
        return coefficientScale > zeroThreshold(
            polynomial: polynomial,
            context: context
        )
    }

    func candidates(
        context: any HeightQuadraticIntersectionContext,
        options: CurveSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> [CertifiedIntersectionCandidate] {
        let polynomial = polynomial(context: context)
        let coefficients = polynomial.coefficients
        guard coefficients.allSatisfy(\.isFinite),
              polynomial.forwardErrorScale.isFinite else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                tolerance: tolerance,
                message: "Height-quadratic elimination produced non-finite coefficients."
            )
        }
        let coefficientScale = coefficients.map(abs).max() ?? 0.0
        guard coefficientScale > zeroThreshold(
            polynomial: polynomial,
            context: context
        ) else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                tolerance: tolerance,
                message: "Height-quadratic elimination was invoked outside its non-degenerate eligibility contract."
            )
        }
        let normalizedCoefficients = coefficients.map {
            $0 / coefficientScale
        }
        let polynomialDegree = effectiveDegree(normalizedCoefficients)
        guard polynomialDegree <= options.maximumPolynomialDegree else {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                tolerance: tolerance,
                message: "Height-quadratic elimination exceeded the requested polynomial-degree limit."
            )
        }
        let solver = try RealPolynomialRootSolver(
            rootTolerance: max(
                tolerance.angle * 0.001,
                Double.ulpOfOne * 64.0
            ),
            residualTolerance: max(
                tolerance.relative * 0.001,
                Double.ulpOfOne * 64.0
            ),
            coefficientTolerance: Double.ulpOfOne * 128.0
        )
        var tangentHalfAngles = try solver.realRoots(
            coefficients: normalizedCoefficients
        )
        if polynomialDegree > 1 {
            let derivative = (1...polynomialDegree).map { index in
                normalizedCoefficients[index] * Double(index)
            }
            let residualTolerance = resultantResidualTolerance(
                polynomial: polynomial,
                coefficientScale: coefficientScale,
                tolerance: tolerance
            )
            for stationaryPoint in try solver.realRoots(
                coefficients: derivative
            ) where abs(evaluate(
                normalizedCoefficients,
                at: stationaryPoint
            )) <= residualTolerance {
                tangentHalfAngles.append(stationaryPoint)
            }
        }
        var angles = tangentHalfAngles.map {
            normalizedAngle(2.0 * atan($0))
        }
        if try verifiedCandidates(
            at: Double.pi,
            context: context,
            tolerance: tolerance
        ).isEmpty == false {
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
                message: "Height-quadratic intersection exceeded the requested candidate limit."
            )
        }

        var candidates: [CertifiedIntersectionCandidate] = []
        for angle in angles {
            let angleCandidates = try verifiedCandidates(
                at: angle,
                context: context,
                tolerance: tolerance
            )
            guard candidates.count + angleCandidates.count
                    <= options.maximumCandidateCount else {
                throw KernelError(
                    phase: .geometry,
                    code: .resourceLimitExceeded,
                    tolerance: tolerance,
                    message: "Height-quadratic candidate recovery exceeded the requested candidate limit."
                )
            }
            candidates.append(contentsOf: angleCandidates)
        }
        return candidates
    }

    private func polynomial(
        context: any HeightQuadraticIntersectionContext
    ) -> HeightQuadraticResultantPolynomial {
        polynomialBuilder.polynomial(
            first: context.sourceEquation,
            second: context.targetEquation
        )
    }

    private func zeroThreshold(
        polynomial: HeightQuadraticResultantPolynomial,
        context: any HeightQuadraticIntersectionContext
    ) -> Double {
        max(
            polynomial.forwardErrorScale,
            pow(context.characteristicLength, 4.0)
        ) * Double.ulpOfOne * 65_536.0
    }

    private func resultantResidualTolerance(
        polynomial: HeightQuadraticResultantPolynomial,
        coefficientScale: Double,
        tolerance: ModelingTolerance
    ) -> Double {
        let normalizedForwardError =
            polynomial.forwardErrorScale / coefficientScale
        return max(
            tolerance.relative * 0.001,
            Double.ulpOfOne * 64.0,
            normalizedForwardError * Double.ulpOfOne * 65_536.0
        )
    }

    private func evaluate(
        _ coefficients: [Double],
        at value: Double
    ) -> Double {
        coefficients.reversed().reduce(0.0) { partial, coefficient in
            partial * value + coefficient
        }
    }

    private func verifiedCandidates(
        at angle: Double,
        context: any HeightQuadraticIntersectionContext,
        tolerance: ModelingTolerance
    ) throws -> [CertifiedIntersectionCandidate] {
        var candidates: [CertifiedIntersectionCandidate] = []
        for point in try context.candidatePoints(
            atAngle: angle,
            tolerance: tolerance
        ) {
            let sourceResidual = try surfaceResidual(
                at: point,
                on: context.sourceSurface,
                tolerance: tolerance
            )
            let targetResidual = try surfaceResidual(
                at: point,
                on: context.targetSurface,
                tolerance: tolerance
            )
            guard let sourceResidual, let targetResidual else {
                continue
            }
            candidates.append(CertifiedIntersectionCandidate(
                point: point,
                residual: max(sourceResidual, targetResidual),
                iterations: 0
            ))
        }
        return candidates
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
}
