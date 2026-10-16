import CADCore
import CADGeometry

package struct DraftedSectionPairBuilder: Sendable {
    package init() {}

    package func pair(curve: Curve3D, parameters: ScalarInterval, normal: Vector3D,
                      axis: Vector3D, pull: Vector3D, lowerHeight: Double,
                      upperHeight: Double, angle: Double,
                      tolerance: ModelingTolerance) throws -> (lower: BSplineCurve3D, upper: BSplineCurve3D) {
        var execution = OriginalQueryExecution(budget: try OriginalQueryBudget(),
            limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32))
        return try legacyPair(curve: curve, parameters: parameters, normal: normal, axis: axis,
            pull: pull, lowerHeight: lowerHeight, upperHeight: upperHeight, angle: angle,
            tolerance: tolerance, using: &execution)
    }

    package func legacyPair(curve: Curve3D, parameters: ScalarInterval, normal: Vector3D,
        axis: Vector3D, pull: Vector3D, lowerHeight: Double, upperHeight: Double,
        angle: Double, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> (lower: BSplineCurve3D, upper: BSplineCurve3D) {
        // The historical numerical convenience keeps its candidate source policy.
        let first = try DraftedSectionCurveSource(curve: curve, normal: normal, axis: axis,
            pull: pull, height: lowerHeight, angle: angle, tolerance: tolerance, using: &execution)
        let second = try DraftedSectionCurveSource(curve: curve, normal: normal, axis: axis,
            pull: pull, height: upperHeight, angle: angle, tolerance: tolerance, using: &execution)
        let requirements = GeometryConversionRequirements(maximumPositionError: tolerance.distance * 0.25,
            maximumTangentAngle: tolerance.angle, maximumCurvatureError: tolerance.distance)
        let converter = CertifiedGeometryConverter()
        var count = 1
        for _ in 0..<requirements.maximumCandidateCount {
            try CurrentTaskCancellationChecker().checkCancellation()
            guard count <= (requirements.maximumControlPointCount - 1) / 3 else {
                throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                    message: "Draft sections exceeded their shared control budget.")
            }
            let breaks = try (0...count).map { index in
                    if index == 0 { return parameters.lower }
                if index == count { return parameters.upper }
                let fraction = Double(index) / Double(count)
                let parameter = parameters.lower * (1 - fraction) + parameters.upper * fraction
                guard parameter.isFinite else { throw GeometryConversionError.invalidInput("Draft candidate station overflowed its native label range.") }
                return parameter
            }
            do {
                let lower = try converter.interpolateCurve(source: first, at: breaks,
                    requirements: requirements, tolerance: tolerance, using: &execution).curve
                let upper = try converter.interpolateCurve(source: second, at: breaks,
                    requirements: requirements, tolerance: tolerance, using: &execution).curve
                guard lower.degree == upper.degree, lower.knots == upper.knots, lower.weights == upper.weights else {
                    throw KernelError(phase: .geometry, code: .classificationFailure, tolerance: tolerance,
                        message: "Draft section certificates did not retain one shared interpolation basis.")
                }
                return (lower, upper)
            } catch GeometryConversionError.toleranceRejected {
                count *= 2
            }
        }
        throw GeometryConversionError.toleranceRejected
    }
    package func pair(curve: Curve3D, parameters: ScalarInterval, normal: Vector3D,
        axis: Vector3D, pull: Vector3D, lowerHeight: Double,
        upperHeight: Double, angle: Double, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> (lower: BSplineCurve3D, upper: BSplineCurve3D) {
        let result = try persistentPair(curve: curve, parameters: parameters, normal: normal,
            axis: axis, pull: pull, lowerHeight: lowerHeight, upperHeight: upperHeight,
            angle: angle, tolerance: tolerance, using: &execution)
        return (result.lowerImage, result.upperImage)
    }

    /// Retains one original traversal alongside fresh certified endpoint-section images.
    package func persistentPair(curve: Curve3D, parameters: ScalarInterval, normal: Vector3D,
        axis: Vector3D, pull: Vector3D, lowerHeight: Double, upperHeight: Double, angle: Double,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> OriginalDraftedSectionPair {
        let generator = try OriginalCurveRootSpan3D(source: curve,
            start: .authored(parameters.lower), end: .authored(parameters.upper),
            maximumParameterWidth: curve.parameterDomain.parameterResolution(tolerance: tolerance),
            maximumSubdivisionDepth: min(32, execution.effectiveLimits.maximumSubdivisionDepth), tolerance: tolerance,
            usage: &execution,
            maximumSpanCount: min(4096, execution.effectiveLimits.maximumSpans),
            remainingSourceDepth: execution.effectiveLimits.remainingSourceDepth,
            maximumAlgebraicDepth: execution.effectiveLimits.maximumValueDepth)
        let bottom = try OriginalDraftedCurve3D(generator: generator, normal: normal, axis: axis,
            pull: pull, height: lowerHeight, angle: angle,
            remainingSourceDepth: execution.effectiveLimits.remainingSourceDepth, tolerance: tolerance, usage: &execution)
        let top = try OriginalDraftedCurve3D(generator: generator, normal: normal, axis: axis,
            pull: pull, height: upperHeight, angle: angle,
            remainingSourceDepth: execution.effectiveLimits.remainingSourceDepth, tolerance: tolerance, usage: &execution)
        let wall = try OriginalDraftedRuledSurface3D(start: bottom, endHeight: upperHeight,
            remainingSourceDepth: execution.effectiveLimits.remainingSourceDepth, tolerance: tolerance, usage: &execution)
        let first = try OriginalDraftedCurveConversionSource(source: bottom, using: &execution)
        let second = try OriginalDraftedCurveConversionSource(source: top, using: &execution)
        let requirements = GeometryConversionRequirements(maximumPositionError: tolerance.distance * 0.25,
            maximumTangentAngle: tolerance.angle, maximumCurvatureError: tolerance.distance)
        let converter = CertifiedGeometryConverter()
        var count = 1
        for _ in 0..<requirements.maximumCandidateCount {
            try CurrentTaskCancellationChecker().checkCancellation(); try execution.consumeWork(1)
            guard count <= (requirements.maximumControlPointCount - 1) / 3 else {
                throw GeometryConversionError.resourceLimitExceeded("Original draft sections exhausted their unchanged shared control allowance.")
            }
            try execution.retainStorage(bytes: (count + 1) * MemoryLayout<Double>.stride)
            var breaks: [Double] = []; breaks.reserveCapacity(count + 1)
            for index in 0...count { try execution.consumeWork(1); breaks.append(Double(index) / Double(count)) }
            do {
                let lower = try converter.interpolateCurve(source: first, at: breaks, requirements: requirements,
                    tolerance: tolerance, using: &execution).curve
                let upper = try converter.interpolateCurve(source: second, at: breaks, requirements: requirements,
                    tolerance: tolerance, using: &execution).curve
                guard lower.degree == upper.degree, lower.knots == upper.knots, lower.weights == upper.weights else {
                    throw KernelError(phase: .geometry, code: .classificationFailure, tolerance: tolerance,
                        message: "Original draft endpoint images do not retain the same construction basis.")
                }
                return .init(lowerImage: lower, upperImage: upper, lowerSource: bottom, upperSource: top, wall: wall)
            } catch GeometryConversionError.toleranceRejected { count *= 2 }
        }
        throw GeometryConversionError.toleranceRejected
    }

}
