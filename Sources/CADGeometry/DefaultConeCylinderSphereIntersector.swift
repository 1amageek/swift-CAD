import CADCore
import Foundation

struct DefaultConeCylinderSphereIntersector:
    ConeCylinderSphereIntersecting
{
    private let polynomialBuilder:
        any ConeCylinderSpherePolynomialBuilding
    private let candidateVerifier:
        any CertifiedIntersectionCandidateVerifying

    init(
        polynomialBuilder:
            any ConeCylinderSpherePolynomialBuilding =
                DefaultConeCylinderSpherePolynomialBuilder(),
        candidateVerifier:
            any CertifiedIntersectionCandidateVerifying =
                DefaultCertifiedIntersectionCandidateVerifier()
    ) {
        self.polynomialBuilder = polynomialBuilder
        self.candidateVerifier = candidateVerifier
    }

    func intersections(
        curve: CertifiedConeCylinderIntersectionCurve,
        sphereSurface: Surface3D,
        options: CurveSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> [CurveSurfaceIntersection] {
        let context = try ConeCylinderSphereIntersectionContext(
            coneSurface: curve.coneSurface,
            cylinderSurface: curve.cylinderSurface,
            sphereSurface: sphereSurface,
            tolerance: tolerance
        )
        let polynomial = polynomialBuilder.polynomial(context: context)
        let coefficients = polynomial.coefficients
        guard coefficients.allSatisfy(\.isFinite) else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                tolerance: tolerance,
                message: "Cone-cylinder sphere elimination produced non-finite coefficients."
            )
        }
        let coefficientScale = coefficients.map(abs).max() ?? 0.0
        let zeroThreshold = max(
            polynomial.forwardErrorScale,
            pow(context.characteristicLength, 4.0)
        ) * Double.ulpOfOne * 65_536.0
        guard polynomial.forwardErrorScale.isFinite,
              zeroThreshold.isFinite else {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                tolerance: tolerance,
                message: "Cone-cylinder sphere elimination exceeded the finite arithmetic envelope."
            )
        }
        if coefficientScale <= zeroThreshold {
            try rejectContinuousOverlap(
                curve: curve,
                sphereSurface: sphereSurface,
                tolerance: tolerance
            )
            if coefficientScale == 0.0 {
                return []
            }
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
                message: "Cone-cylinder sphere elimination exceeded the requested polynomial-degree limit."
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
                message: "Cone-cylinder sphere intersection exceeded the requested candidate limit."
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
                    message: "Cone-cylinder sphere candidate recovery exceeded the requested candidate limit."
                )
            }
            candidates.append(contentsOf: angleCandidates)
        }
        return try candidateVerifier.intersections(
            candidates: candidates,
            curve: .coneCylinder(curve),
            targetSurface: sphereSurface,
            options: options,
            tolerance: tolerance
        )
    }

    private func rejectContinuousOverlap(
        curve: CertifiedConeCylinderIntersectionCurve,
        sphereSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws {
        // A resultant inside the forward-error envelope is consistent with
        // the cone and sphere height quadratics sharing an algebraic branch
        // over the cylinder angle.
        // Full components retain one root branch. Bounded and nodal
        // components traverse both root branches on their two open halves,
        // so two interior witnesses from the same half identify whether the
        // shared branch belongs to this certified component.
        let fractions = [0.125, 0.375, 0.625, 0.875]
        var membership: [Bool] = []
        for fraction in fractions {
            let point = try curve.point(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
            membership.append(try surfaceResidual(
                at: point,
                on: sphereSurface,
                tolerance: tolerance
            ) != nil)
        }
        let overlapsContinuously: Bool
        switch curve.componentKind {
        case .negativeFullBranch, .positiveFullBranch,
             .tangentFullBranch, .rulingParallelLinear:
            overlapsContinuously = membership.allSatisfy { $0 }
        case .boundedAngularInterval, .apexLowerNodeInterval,
             .apexUpperNodeInterval:
            overlapsContinuously = (membership[0] && membership[1])
                || (membership[2] && membership[3])
        }
        guard overlapsContinuously == false else {
            throw KernelError(
                phase: .geometry,
                code: .nonDiscreteIntersection,
                tolerance: tolerance,
                message: "The target sphere overlaps a continuous branch of the certified cone-cylinder component."
            )
        }
    }

    private func verifiedCandidates(
        at angle: Double,
        context: ConeCylinderSphereIntersectionContext,
        tolerance: ModelingTolerance
    ) throws -> [CertifiedIntersectionCandidate] {
        var candidates: [CertifiedIntersectionCandidate] = []
        for point in try context.spherePoints(
            atCylinderAngle: angle,
            tolerance: tolerance
        ) {
            let coneResidual = try surfaceResidual(
                at: point,
                on: context.coneSurface,
                tolerance: tolerance
            )
            let sphereResidual = try surfaceResidual(
                at: point,
                on: context.sphereSurface,
                tolerance: tolerance
            )
            guard let coneResidual, let sphereResidual else {
                continue
            }
            candidates.append(CertifiedIntersectionCandidate(
                point: point,
                residual: max(coneResidual, sphereResidual),
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
