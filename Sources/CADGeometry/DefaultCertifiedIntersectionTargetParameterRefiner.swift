import CADCore

struct DefaultCertifiedIntersectionTargetParameterRefiner:
    CertifiedIntersectionTargetParameterRefining
{
    private let implicitDifferentialEvaluator:
        any AnalyticSurfaceImplicitDifferentialEvaluating

    init(
        implicitDifferentialEvaluator:
            any AnalyticSurfaceImplicitDifferentialEvaluating =
                DefaultAnalyticSurfaceImplicitDifferentialEvaluator()
    ) {
        self.implicitDifferentialEvaluator = implicitDifferentialEvaluator
    }

    func refinedParameter(
        initialParameter: Double,
        curve: CertifiedIntersectionCurve3D,
        target: CertifiedAnalyticIntersectionTarget,
        restrictedTo range: ScalarInterval?,
        maximumIterations: Int,
        tolerance: ModelingTolerance
    ) throws -> (parameter: Double, iterations: Int) {
        return try refineAnalyticParameter(
            initialParameter: initialParameter,
            curve: curve,
            target: target.canonicalSurface,
            range: range,
            maximumIterations: maximumIterations,
            tolerance: tolerance
        )
    }

    private func refineAnalyticParameter(
        initialParameter: Double,
        curve: CertifiedIntersectionCurve3D,
        target: CanonicalAnalyticSurface,
        range: ScalarInterval?,
        maximumIterations: Int,
        tolerance: ModelingTolerance
    ) throws -> (parameter: Double, iterations: Int) {
        let lower = max(range?.lower ?? 0.0, 0.0)
        let upper = min(range?.upper ?? 1.0, 1.0)
        guard initialParameter.isFinite,
              upper >= lower,
              maximumIterations > 0 else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Certified intersection parameter refinement received an invalid search contract."
            )
        }
        let modelCurve = Curve3D.certifiedIntersection(curve)
        var parameter = min(max(initialParameter, lower), upper)
        var lastStep = Double.infinity
        var seeksStationaryContact = false
        for iteration in 0..<maximumIterations {
            let geometry = try modelCurve.differentialGeometry(
                at: parameter,
                tolerance: tolerance
            )
            let implicit = try implicitDifferentialEvaluator.differential(
                at: geometry.position,
                on: target
            )
            let first = implicit.gradient.dot(
                geometry.firstDerivative
            )
            let second = try implicitDifferentialEvaluator
                .curveSecondDerivative(
                    geometry: geometry,
                    implicitGradient: implicit.gradient,
                    surface: target
                )
            let arithmeticFloor = (
                Double.ulpOfOne * 4_096.0
                    * max(
                        abs(implicit.value),
                        implicit.gradient.length,
                        geometry.firstDerivative.length,
                        1.0
                    )
            ).nextUp
            let incidenceScale = max(
                implicit.gradient.length
                    * geometry.firstDerivative.length,
                Double.leastNonzeroMagnitude
            )
            let normalizedIncidence = abs(first) / incidenceScale
            if normalizedIncidence <= tolerance.angle {
                return (parameter, iteration)
            }
            let derivativeFloor = (
                Double.ulpOfOne * 256.0
                    * max(abs(first), implicit.gradient.length, 1.0)
            ).nextUp
            let firstSquared = first * first
            if abs(first) > derivativeFloor,
               firstSquared.isFinite,
               firstSquared > 0.0 {
                let multiplicityIndicator =
                    implicit.value * second / firstSquared
                if multiplicityIndicator >= 0.2,
                   multiplicityIndicator <= 0.8 {
                    seeksStationaryContact = true
                }
            }
            if abs(implicit.value) <= arithmeticFloor,
               seeksStationaryContact == false {
                return (parameter, iteration)
            }
            guard abs(first) > derivativeFloor else {
                throw KernelError(
                    phase: .geometry,
                    code: .singularSystem,
                    residual: abs(first),
                    tolerance: tolerance,
                    message: "Certified intersection target refinement reached a stationary non-root candidate."
                )
            }
            let correction: Double
            if seeksStationaryContact {
                let secondDerivativeFloor = (
                    Double.ulpOfOne * 256.0
                        * max(abs(second), incidenceScale, 1.0)
                ).nextUp
                guard abs(second) > secondDerivativeFloor else {
                    throw KernelError(
                        phase: .geometry,
                        code: .singularSystem,
                        residual: abs(second),
                        tolerance: tolerance,
                        message: "Certified intersection tangent refinement lost its nonzero contact curvature."
                    )
                }
                correction = first / second
            } else {
                correction = implicit.value / first
            }
            var candidate = min(
                max(parameter - correction, lower),
                upper
            )
            guard candidate.isFinite else {
                throw KernelError(
                    phase: .geometry,
                    code: .resourceLimitExceeded,
                    tolerance: tolerance,
                    message: "Certified intersection target refinement exceeded finite arithmetic."
                )
            }
            var candidateValue = try implicitValue(
                parameter: candidate,
                curve: modelCurve,
                target: target,
                tolerance: tolerance
            )
            var lineSearchSteps = 0
            while abs(candidateValue) > abs(implicit.value),
                  lineSearchSteps < 12 {
                candidate = parameter + (candidate - parameter) * 0.5
                candidateValue = try implicitValue(
                    parameter: candidate,
                    curve: modelCurve,
                    target: target,
                    tolerance: tolerance
                )
                lineSearchSteps += 1
            }
            lastStep = abs(candidate - parameter)
            parameter = candidate
            let parameterTolerance = max(
                tolerance.relative,
                Double.ulpOfOne * max(abs(parameter), 1.0) * 256.0
            )
            if lastStep <= parameterTolerance,
               seeksStationaryContact == false {
                return (parameter, iteration + 1)
            }
        }
        throw KernelError(
            phase: .geometry,
            code: .resourceLimitExceeded,
            residual: lastStep,
            tolerance: tolerance,
            message: "Certified intersection target refinement exhausted its iteration budget."
        )
    }

    private func implicitValue(
        parameter: Double,
        curve: Curve3D,
        target: CanonicalAnalyticSurface,
        tolerance: ModelingTolerance
    ) throws -> Double {
        let geometry = try curve.differentialGeometry(
            at: parameter,
            tolerance: tolerance
        )
        return try implicitDifferentialEvaluator.differential(
            at: geometry.position,
            on: target
        ).value
    }
}
