import CADCore
#if !hasFeature(Embedded)
import Foundation
#elseif canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#else
#error("CADGeometry numeric algorithms require the target C math module.")
#endif

extension CertifiedBoundedPlaneConeIntersectionCurve {
    func spatialDifferentialMagnitudeBounds(
        fromNormalizedFraction lowerFraction: Double,
        toNormalizedFraction upperFraction: Double,
        tolerance: ModelingTolerance
    ) throws -> SpatialDifferentialMagnitudeBounds {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try spatialDifferentialMagnitudeBounds(fromNormalizedFraction: lowerFraction, toNormalizedFraction: upperFraction, tolerance: tolerance, using: &execution)
    }

    func spatialDifferentialMagnitudeBounds(
        fromNormalizedFraction lowerFraction: Double,
        toNormalizedFraction upperFraction: Double,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> SpatialDifferentialMagnitudeBounds {
        try execution.checkpoint()
        let result = try spatialDifferentialMagnitudeBoundsImplementation(fromNormalizedFraction: lowerFraction, toNormalizedFraction: upperFraction, tolerance: tolerance, using: &execution)
        try execution.checkpoint()
        return result
    }


    private func spatialDifferentialMagnitudeBoundsImplementation(
        fromNormalizedFraction lowerFraction: Double,
        toNormalizedFraction upperFraction: Double,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> SpatialDifferentialMagnitudeBounds {
        try execution.checkpoint()
        try execution.consumeWork(1)
        try validate(tolerance: tolerance, using: &execution)
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
        let third: Double

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
                , using: &execution),
                try upperProduct(
                    curve.conjugateRadius,
                    hyperbolicCosine,
                    tolerance: tolerance
                , using: &execution)
            ).nextUp
            let sourceSecond = hypot(
                try upperProduct(
                    curve.transverseRadius,
                    hyperbolicCosine,
                    tolerance: tolerance
                , using: &execution),
                try upperProduct(
                    curve.conjugateRadius,
                    hyperbolicSine,
                    tolerance: tolerance
                , using: &execution)
            ).nextUp
            first = try upperProduct(
                sourceFirst,
                parameterSpan,
                tolerance: tolerance
            , using: &execution)
            second = try upperProduct(
                try upperProduct(
                    sourceSecond,
                    parameterSpan,
                    tolerance: tolerance
                , using: &execution),
                parameterSpan,
                tolerance: tolerance
            , using: &execution)
            third = try upperProduct(
                try upperProduct(
                    try upperProduct(
                        sourceFirst,
                        parameterSpan,
                        tolerance: tolerance
                    , using: &execution),
                    parameterSpan,
                    tolerance: tolerance
                , using: &execution),
                parameterSpan,
                tolerance: tolerance
            , using: &execution)
        case let .parabola(curve):
            let scaledParameter = try upperProduct(
                maximumParameterMagnitude,
                (1.0 / (2.0 * curve.focalLength)).nextUp,
                tolerance: tolerance
            , using: &execution)
            let sourceFirst = hypot(1.0, scaledParameter).nextUp
            let sourceSecond = (1.0 / (2.0 * curve.focalLength)).nextUp
            first = try upperProduct(
                sourceFirst,
                parameterSpan,
                tolerance: tolerance
            , using: &execution)
            second = try upperProduct(
                try upperProduct(
                    sourceSecond,
                    parameterSpan,
                    tolerance: tolerance
                , using: &execution),
                parameterSpan,
                tolerance: tolerance
            , using: &execution)
            third = 0.0
        case .line, .circle, .arc, .ellipse, .planeTorus:
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Bounded plane-cone differential bounds require a hyperbola or parabola."
            )
        }

        guard first.isFinite, second.isFinite, third.isFinite else {
            throw resourceFailure(
                tolerance: tolerance,
                message: "Bounded plane-cone differential certification exceeded finite arithmetic."
            )
        }
        return SpatialDifferentialMagnitudeBounds(
            first: first.nextUp,
            second: second.nextUp,
            third: third.nextUp
        )
    }

    private func upperProduct<A: ExactScalarAdmission & ~Copyable>(
        _ first: Double,
        _ second: Double,
        tolerance: ModelingTolerance
    , using execution: inout A) throws -> Double {
        try execution.checkpoint()
        try execution.consumeWork(1)
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
