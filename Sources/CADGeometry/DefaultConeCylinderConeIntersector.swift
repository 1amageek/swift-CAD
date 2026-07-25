import CADCore
import Foundation

struct DefaultConeCylinderConeIntersector: ConeCylinderConeIntersecting {
    private let polynomialBuilder:
        any ConeCylinderConePolynomialBuilding
    private let candidateVerifier:
        any CertifiedIntersectionCandidateVerifying

    init(
        polynomialBuilder:
            any ConeCylinderConePolynomialBuilding =
                DefaultConeCylinderConePolynomialBuilder(),
        candidateVerifier:
            any CertifiedIntersectionCandidateVerifying =
                DefaultCertifiedIntersectionCandidateVerifier()
    ) {
        self.polynomialBuilder = polynomialBuilder
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
        let polynomial = polynomialBuilder.polynomial(context: context)
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
        let polynomial = polynomialBuilder.polynomial(context: context)
        let coefficients = polynomial.coefficients
        guard coefficients.allSatisfy(\.isFinite),
              polynomial.forwardErrorScale.isFinite else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                tolerance: tolerance,
                message: "Cone-cylinder cone elimination produced non-finite coefficients."
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
                message: "Cone-cylinder cone elimination was invoked outside its non-degenerate eligibility contract."
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
                message: "Cone-cylinder cone elimination exceeded the requested polynomial-degree limit."
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
        var angles = try solver.realRoots(
            coefficients: normalizedCoefficients
        ).map {
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
                message: "Cone-cylinder cone intersection exceeded the requested candidate limit."
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
                    message: "Cone-cylinder cone candidate recovery exceeded the requested candidate limit."
                )
            }
            candidates.append(contentsOf: angleCandidates)
        }
        return try candidateVerifier.intersections(
            candidates: candidates,
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

    private func zeroThreshold(
        polynomial: ConeCylinderConePolynomial,
        context: ConeCylinderConeIntersectionContext
    ) -> Double {
        max(
            polynomial.forwardErrorScale,
            pow(context.characteristicLength, 4.0)
        ) * Double.ulpOfOne * 65_536.0
    }

    private func verifiedCandidates(
        at angle: Double,
        context: ConeCylinderConeIntersectionContext,
        tolerance: ModelingTolerance
    ) throws -> [CertifiedIntersectionCandidate] {
        var candidates: [CertifiedIntersectionCandidate] = []
        for point in try context.candidatePoints(
            atCylinderAngle: angle,
            tolerance: tolerance
        ) {
            let sourceResidual = try surfaceResidual(
                at: point,
                on: context.sourceConeSurface,
                tolerance: tolerance
            )
            let targetResidual = try surfaceResidual(
                at: point,
                on: context.targetConeSurface,
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
