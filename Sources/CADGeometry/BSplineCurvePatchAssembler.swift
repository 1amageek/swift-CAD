import CADCore
import Foundation

struct BSplineCurvePatchAssembler {
    func trimmedCurve(
        source: BSplineCurve3D,
        lower: Double,
        upper: Double,
        tolerance: ModelingTolerance
    ) throws -> BSplineCurve3D {
        try source.validate(tolerance: tolerance)
        guard try source.domain.containsSpan(
            from: lower,
            to: upper,
            tolerance: tolerance
        ) else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Rational B-spline curve trimming exceeds the source parameter domain."
            )
        }
        let requestedInterval = try ScalarInterval(
            lower: lower,
            upper: upper
        )
        let sourcePatches = try BSplineCurveBezierDecomposer().curvePatches(
            curve: source,
            intersecting: requestedInterval,
            tolerance: tolerance
        )
        let parameterResolution = resolution(
            values: [lower, upper],
            tolerance: tolerance
        )
        let breaks = parameterBreaks(
            lower: lower,
            upper: upper,
            sourceValues: sourcePatches.flatMap { [$0.lower, $0.upper] },
            resolution: parameterResolution
        )
        let spanCount = breaks.count - 1
        guard spanCount > 0 else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Rational B-spline curve trimming produced no positive parameter span."
            )
        }
        var patches: [RationalBezierCurvePatch3D] = []
        patches.reserveCapacity(spanCount)
        for index in 0..<spanCount {
            let requested = (breaks[index], breaks[index + 1])
            guard let sourcePatch = sourcePatches.first(where: { patch in
                patch.lower <= requested.0 + parameterResolution
                    && patch.upper >= requested.1 - parameterResolution
            }) else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    tolerance: tolerance,
                    message: "Rational B-spline curve trimming could not cover a requested parameter span."
                )
            }
            patches.append(try sourcePatch.trimmed(
                from: requested.0,
                to: requested.1,
                tolerance: tolerance
            ))
        }

        let controlCount = spanCount * source.degree + 1
        var points = Array<Point3D?>(repeating: nil, count: controlCount)
        var weights = Array<Double?>(repeating: nil, count: controlCount)
        for span in 0..<spanCount {
            let patch = patches[span]
            for localIndex in 0...source.degree {
                let targetIndex = span * source.degree + localIndex
                let point = patch.controlPoints[localIndex]
                let weight = patch.weights[localIndex]
                if let existingPoint = points[targetIndex],
                   let existingWeight = weights[targetIndex] {
                    try validateSharedControl(
                        firstPoint: existingPoint,
                        firstWeight: existingWeight,
                        secondPoint: point,
                        secondWeight: weight,
                        tolerance: tolerance
                    )
                } else {
                    points[targetIndex] = point
                    weights[targetIndex] = weight
                }
            }
        }
        let resolvedPoints = try points.map { value -> Point3D in
            guard let value else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    tolerance: tolerance,
                    message: "Rational B-spline curve trimming left a control point uninitialized."
                )
            }
            return value
        }
        let resolvedWeights = try weights.map { value -> Double in
            guard let value else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    tolerance: tolerance,
                    message: "Rational B-spline curve trimming left a control weight uninitialized."
                )
            }
            return value
        }
        let result = BSplineCurve3D(
            degree: source.degree,
            knots: knotVector(breaks: breaks, degree: source.degree),
            controlPoints: resolvedPoints,
            weights: resolvedWeights
        )
        try result.validate(tolerance: tolerance)
        try verify(
            result: result,
            source: source,
            breaks: breaks,
            tolerance: tolerance
        )
        return result
    }

    private func validateSharedControl(
        firstPoint: Point3D,
        firstWeight: Double,
        secondPoint: Point3D,
        secondWeight: Double,
        tolerance: ModelingTolerance
    ) throws {
        let pointResidual = (firstPoint - secondPoint).length.nextUp
        let weightScale = max(1.0, abs(firstWeight), abs(secondWeight))
        let weightResidual = abs(firstWeight - secondWeight).nextUp
        guard pointResidual <= tolerance.distance,
              weightResidual <= max(tolerance.relative * weightScale, Double.ulpOfOne * weightScale * 512.0) else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: max(pointResidual, weightResidual),
                tolerance: tolerance,
                message: "Adjacent rational Bezier curve spans disagree at a shared homogeneous control point."
            )
        }
    }

    private func verify(
        result: BSplineCurve3D,
        source: BSplineCurve3D,
        breaks: [Double],
        tolerance: ModelingTolerance
    ) throws {
        var maximumResidual = 0.0
        for parameter in samples(from: breaks) {
            let expected = try source.point(at: parameter, tolerance: tolerance)
            let actual = try result.point(at: parameter, tolerance: tolerance)
            maximumResidual = max(maximumResidual, (actual - expected).length.nextUp)
        }
        guard maximumResidual <= tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: maximumResidual,
                tolerance: tolerance,
                message: "Rational B-spline trimmed curve failed exact-locus verification."
            )
        }
    }

    private func samples(from breaks: [Double]) -> [Double] {
        var result: [Double] = []
        for index in 0..<(breaks.count - 1) {
            if result.last != breaks[index] {
                result.append(breaks[index])
            }
            result.append(breaks[index] + (breaks[index + 1] - breaks[index]) * 0.5)
        }
        if let last = breaks.last {
            result.append(last)
        }
        return result
    }

    private func parameterBreaks(
        lower: Double,
        upper: Double,
        sourceValues: [Double],
        resolution: Double
    ) -> [Double] {
        let interior = sourceValues
            .filter { $0 > lower + resolution && $0 < upper - resolution }
            .sorted()
        var result = [lower]
        for value in interior where abs(value - (result.last ?? lower)) > resolution {
            result.append(value)
        }
        result.append(upper)
        return result
    }

    private func knotVector(breaks: [Double], degree: Int) -> [Double] {
        Array(repeating: breaks[0], count: degree + 1)
            + breaks.dropFirst().dropLast().flatMap { value in
                Array(repeating: value, count: degree)
            }
            + Array(repeating: breaks[breaks.count - 1], count: degree + 1)
    }

    private func resolution(
        values: [Double],
        tolerance: ModelingTolerance
    ) -> Double {
        let scale = max(1.0, values.map(abs).max() ?? 1.0)
        return max(
            tolerance.relative * scale,
            Double.ulpOfOne * scale * 512.0
        )
    }
}
