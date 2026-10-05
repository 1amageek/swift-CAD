import CADCore
import CADGeometry

package struct DraftedSectionPairBuilder: Sendable {
    package init() {}

    package func pair(curve: Curve3D, parameters: ScalarInterval, normal: Vector3D,
                      axis: Vector3D, pull: Vector3D, lowerHeight: Double,
                      upperHeight: Double, angle: Double,
                      tolerance: ModelingTolerance,
                      admission: GeometryConversionAdmission? = nil) throws -> (lower: BSplineCurve3D, upper: BSplineCurve3D) {
        if let admission {
            let result = try persistentPair(curve: curve, parameters: parameters, normal: normal,
                axis: axis, pull: pull, lowerHeight: lowerHeight, upperHeight: upperHeight,
                angle: angle, tolerance: tolerance, admission: admission)
            return (result.lowerImage, result.upperImage)
        }
        // Legacy callers without a composing admission retain their original
        // convenience conversion policy. Production callers return above.
        let first = try DraftedSectionCurveSource(curve: curve, normal: normal, axis: axis,
            pull: pull, height: lowerHeight, angle: angle, tolerance: tolerance)
        let second = try DraftedSectionCurveSource(curve: curve, normal: normal, axis: axis,
            pull: pull, height: upperHeight, angle: angle, tolerance: tolerance)
        let requirements = GeometryConversionRequirements(maximumPositionError: tolerance.distance * 0.25,
            maximumTangentAngle: tolerance.angle, maximumCurvatureError: tolerance.distance)
        let converter = CertifiedGeometryConverter()
        var count = 1
        for _ in 0..<requirements.maximumCandidateCount {
            try Task.checkCancellation()
            try admission?.chargeWork()
            guard count <= (requirements.maximumControlPointCount - 1) / 3 else {
                throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                    message: "Draft sections exceeded their shared control budget.")
            }
            try admission?.chargeStorage(bytes: (count + 1) * MemoryLayout<Double>.stride)
            let breaks = try (0...count).map { index in
                try admission?.chargeWork()
                if index == 0 { return parameters.lower }
                if index == count { return parameters.upper }
                let fraction = Double(index) / Double(count)
                let parameter = parameters.lower * (1 - fraction) + parameters.upper * fraction
                guard parameter.isFinite else { throw GeometryConversionError.invalidInput("Draft candidate station overflowed its native label range.") }
                return parameter
            }
            do {
                let lower = try converter.interpolateCurve(source: first, at: breaks,
                    requirements: requirements, tolerance: tolerance).curve
                let upper = try converter.interpolateCurve(source: second, at: breaks,
                    requirements: requirements, tolerance: tolerance).curve
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
    /// Retains one original traversal alongside fresh certified endpoint-section images.
    package func persistentPair(curve: Curve3D, parameters: ScalarInterval, normal: Vector3D,
        axis: Vector3D, pull: Vector3D, lowerHeight: Double, upperHeight: Double, angle: Double,
        tolerance: ModelingTolerance, admission: GeometryConversionAdmission) throws -> OriginalDraftedSectionPair {
        var usage = OriginalDraftedConstructionAdmission(admission)
        let generator = try OriginalCurveRootSpan3D(source: curve,
            start: .authored(parameters.lower), end: .authored(parameters.upper),
            maximumParameterWidth: curve.parameterDomain.parameterResolution(tolerance: tolerance),
            maximumSubdivisionDepth: min(32, admission.maximumSubdivisionDepth), tolerance: tolerance,
            storageByteStride: MemoryLayout<UInt32>.stride, usage: &usage,
            maximumSpanCount: min(4096, admission.maximumSpanCount),
            remainingSourceDepth: admission.remainingSourceDepth,
            maximumAlgebraicDepth: admission.maximumAlgebraicDepth ?? 32)
        let bottom = try OriginalDraftedCurve3D(generator: generator, normal: normal, axis: axis,
            pull: pull, height: lowerHeight, angle: angle,
            remainingSourceDepth: admission.remainingSourceDepth, tolerance: tolerance, usage: &usage)
        let top = try OriginalDraftedCurve3D(generator: generator, normal: normal, axis: axis,
            pull: pull, height: upperHeight, angle: angle,
            remainingSourceDepth: admission.remainingSourceDepth, tolerance: tolerance, usage: &usage)
        let wall = try OriginalDraftedRuledSurface3D(start: bottom, endHeight: upperHeight,
            remainingSourceDepth: admission.remainingSourceDepth, tolerance: tolerance, usage: &usage)
        let first = OriginalDraftedCurveConversionSource(source: bottom, admission: admission)
        let second = OriginalDraftedCurveConversionSource(source: top, admission: admission)
        let requirements = GeometryConversionRequirements(maximumPositionError: tolerance.distance * 0.25,
            maximumTangentAngle: tolerance.angle, maximumCurvatureError: tolerance.distance)
        let converter = CertifiedGeometryConverter()
        var count = 1
        for _ in 0..<requirements.maximumCandidateCount {
            try Task.checkCancellation(); try admission.chargeWork()
            guard count <= (requirements.maximumControlPointCount - 1) / 3 else {
                throw GeometryConversionError.resourceLimitExceeded("Original draft sections exhausted their unchanged shared control allowance.")
            }
            try admission.chargeStorage(bytes: (count + 1) * MemoryLayout<Double>.stride)
            var breaks: [Double] = []; breaks.reserveCapacity(count + 1)
            for index in 0...count { try admission.chargeWork(); breaks.append(Double(index) / Double(count)) }
            do {
                let lower = try converter.interpolateCurve(source: first, at: breaks, requirements: requirements,
                    tolerance: tolerance, admission: admission).curve
                let upper = try converter.interpolateCurve(source: second, at: breaks, requirements: requirements,
                    tolerance: tolerance, admission: admission).curve
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
