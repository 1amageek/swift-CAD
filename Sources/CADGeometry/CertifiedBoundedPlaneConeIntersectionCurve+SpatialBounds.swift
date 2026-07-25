import CADCore
import Foundation

extension CertifiedBoundedPlaneConeIntersectionCurve {
    func spatialDifferentialMagnitudeBounds(
        fromNormalizedFraction lowerFraction: Double,
        toNormalizedFraction upperFraction: Double,
        tolerance: ModelingTolerance
    ) throws -> SpatialDifferentialMagnitudeBounds {
        try validate(tolerance: tolerance)
        guard lowerFraction.isFinite,
              upperFraction.isFinite,
              lowerFraction >= -tolerance.relative,
              upperFraction <= 1.0 + tolerance.relative,
              upperFraction - lowerFraction > tolerance.relative else {
            throw GeometryError.invalidDistance(
                upperFraction - lowerFraction
            )
        }
        let clampedLower = min(max(lowerFraction, 0.0), 1.0)
        let clampedUpper = min(max(upperFraction, 0.0), 1.0)
        let parameterSpan = endParameter - startParameter
        let lowerParameter = (
            startParameter + parameterSpan * clampedLower
        ).nextDown
        let upperParameter = (
            startParameter + parameterSpan * clampedUpper
        ).nextUp
        let maximumParameterMagnitude = max(
            abs(lowerParameter),
            abs(upperParameter)
        ).nextUp
        let first: Double
        let second: Double

        switch analyticCurve {
        case let .hyperbola(curve):
            let hyperbolicSine = sinh(maximumParameterMagnitude).nextUp
            let hyperbolicCosine = cosh(maximumParameterMagnitude).nextUp
            guard hyperbolicSine.isFinite,
                  hyperbolicCosine.isFinite else {
                throw resourceFailure(
                    tolerance: tolerance,
                    message: "Bounded hyperbola differential certification exceeded finite arithmetic."
                )
            }
            let sourceFirst = hypot(
                try upperProduct(
                    curve.transverseRadius,
                    hyperbolicSine,
                    tolerance: tolerance
                ),
                try upperProduct(
                    curve.conjugateRadius,
                    hyperbolicCosine,
                    tolerance: tolerance
                )
            ).nextUp
            let sourceSecond = hypot(
                try upperProduct(
                    curve.transverseRadius,
                    hyperbolicCosine,
                    tolerance: tolerance
                ),
                try upperProduct(
                    curve.conjugateRadius,
                    hyperbolicSine,
                    tolerance: tolerance
                )
            ).nextUp
            first = try upperProduct(
                sourceFirst,
                parameterSpan,
                tolerance: tolerance
            )
            second = try upperProduct(
                try upperProduct(
                    sourceSecond,
                    parameterSpan,
                    tolerance: tolerance
                ),
                parameterSpan,
                tolerance: tolerance
            )
        case let .parabola(curve):
            let scaledParameter = try upperProduct(
                maximumParameterMagnitude,
                (1.0 / (2.0 * curve.focalLength)).nextUp,
                tolerance: tolerance
            )
            let sourceFirst = hypot(1.0, scaledParameter).nextUp
            let sourceSecond = (1.0 / (2.0 * curve.focalLength)).nextUp
            first = try upperProduct(
                sourceFirst,
                parameterSpan,
                tolerance: tolerance
            )
            second = try upperProduct(
                try upperProduct(
                    sourceSecond,
                    parameterSpan,
                    tolerance: tolerance
                ),
                parameterSpan,
                tolerance: tolerance
            )
        case .line, .circle, .arc, .ellipse, .planeTorus:
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Bounded plane-cone differential bounds require a hyperbola or parabola."
            )
        }

        guard first.isFinite, second.isFinite else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "Bounded plane-cone differential certification exceeded finite arithmetic."
            )
        }
        return SpatialDifferentialMagnitudeBounds(
            first: first.nextUp,
            second: second.nextUp
        )
    }

    private func upperProduct(
        _ first: Double,
        _ second: Double,
        tolerance: ModelingTolerance
    ) throws -> Double {
        let result = (first * second).nextUp
        guard result.isFinite else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "Bounded plane-cone differential certification exceeded finite arithmetic."
            )
        }
        return result
    }

    private func resourceFailure(
        tolerance: ModelingTolerance,
        message: String
    ) -> KernelError {
        KernelError(
            phase: .geometry,
            code: .resourceLimitExceeded,
            tolerance: tolerance,
            message: message
        )
    }
}
