import CADCore
import Foundation

struct BSplineSurfacePatchAssembler {
    func trimmedSurface(
        source: BSplineSurface3D,
        uBounds: (lower: Double, upper: Double),
        vBounds: (lower: Double, upper: Double),
        tolerance: ModelingTolerance
    ) throws -> BSplineSurface3D {
        try source.validate(tolerance: tolerance)
        guard try source.uDomain.containsSpan(
            from: uBounds.lower,
            to: uBounds.upper,
            tolerance: tolerance
        ), try source.vDomain.containsSpan(
            from: vBounds.lower,
            to: vBounds.upper,
            tolerance: tolerance
        ) else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Rational B-spline surface trimming exceeds the source parameter domain."
            )
        }
        let sourcePatches = try BSplineSurfaceBezierDecomposer().surfacePatches(
            surface: source,
            tolerance: tolerance
        )
        let parameterTolerance = resolution(
            values: [uBounds.lower, uBounds.upper, vBounds.lower, vBounds.upper],
            tolerance: tolerance
        )
        let uBreaks = breaks(
            lower: uBounds.lower,
            upper: uBounds.upper,
            sourceValues: sourcePatches.flatMap { [$0.uLower, $0.uUpper] },
            resolution: parameterTolerance
        )
        let vBreaks = breaks(
            lower: vBounds.lower,
            upper: vBounds.upper,
            sourceValues: sourcePatches.flatMap { [$0.vLower, $0.vUpper] },
            resolution: parameterTolerance
        )
        let uSpanCount = uBreaks.count - 1
        let vSpanCount = vBreaks.count - 1
        guard uSpanCount > 0, vSpanCount > 0 else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Rational B-spline surface trimming produced no positive parameter span."
            )
        }
        var patches: [RationalBezierSurfacePatch3D] = []
        patches.reserveCapacity(uSpanCount * vSpanCount)
        for vIndex in 0..<vSpanCount {
            for uIndex in 0..<uSpanCount {
                let requestedU = (uBreaks[uIndex], uBreaks[uIndex + 1])
                let requestedV = (vBreaks[vIndex], vBreaks[vIndex + 1])
                guard let sourcePatch = sourcePatches.first(where: { patch in
                    patch.uLower <= requestedU.0 + parameterTolerance
                        && patch.uUpper >= requestedU.1 - parameterTolerance
                        && patch.vLower <= requestedV.0 + parameterTolerance
                        && patch.vUpper >= requestedV.1 - parameterTolerance
                }) else {
                    throw KernelError(
                        phase: .geometry,
                        code: .intersectionFailure,
                        tolerance: tolerance,
                        message: "Rational B-spline trimming could not cover the requested parameter cell."
                    )
                }
                patches.append(try sourcePatch.trimmed(
                    uFrom: requestedU.0,
                    uTo: requestedU.1,
                    vFrom: requestedV.0,
                    vTo: requestedV.1,
                    tolerance: tolerance
                ))
            }
        }

        let uControlCount = uSpanCount * source.uDegree + 1
        let vControlCount = vSpanCount * source.vDegree + 1
        var points = Array(
            repeating: Array<Point3D?>(repeating: nil, count: uControlCount),
            count: vControlCount
        )
        var weights = Array(
            repeating: Array<Double?>(repeating: nil, count: uControlCount),
            count: vControlCount
        )
        for vSpan in 0..<vSpanCount {
            for uSpan in 0..<uSpanCount {
                let patch = patches[vSpan * uSpanCount + uSpan]
                for localV in 0...source.vDegree {
                    for localU in 0...source.uDegree {
                        let targetV = vSpan * source.vDegree + localV
                        let targetU = uSpan * source.uDegree + localU
                        let point = patch.controlPoints[localV][localU]
                        let weight = patch.weights[localV][localU]
                        if let existingPoint = points[targetV][targetU],
                           let existingWeight = weights[targetV][targetU] {
                            try validateSharedControl(
                                firstPoint: existingPoint,
                                firstWeight: existingWeight,
                                secondPoint: point,
                                secondWeight: weight,
                                tolerance: tolerance
                            )
                        } else {
                            points[targetV][targetU] = point
                            weights[targetV][targetU] = weight
                        }
                    }
                }
            }
        }
        let resolvedPoints = try points.map { row in
            try row.map { value in
                guard let value else {
                    throw KernelError(
                        phase: .geometry,
                        code: .intersectionFailure,
                        tolerance: tolerance,
                        message: "Rational B-spline trimming left a control point uninitialized."
                    )
                }
                return value
            }
        }
        let resolvedWeights = try weights.map { row in
            try row.map { value in
                guard let value else {
                    throw KernelError(
                        phase: .geometry,
                        code: .intersectionFailure,
                        tolerance: tolerance,
                        message: "Rational B-spline trimming left a control weight uninitialized."
                    )
                }
                return value
            }
        }
        let result = BSplineSurface3D(
            uDegree: source.uDegree,
            vDegree: source.vDegree,
            uKnots: knotVector(breaks: uBreaks, degree: source.uDegree),
            vKnots: knotVector(breaks: vBreaks, degree: source.vDegree),
            controlPoints: resolvedPoints,
            weights: resolvedWeights
        )
        try result.validate(tolerance: tolerance)
        try verify(
            result: result,
            source: source,
            uBreaks: uBreaks,
            vBreaks: vBreaks,
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
                message: "Adjacent rational Bezier patches disagree at a shared homogeneous control point."
            )
        }
    }

    private func verify(
        result: BSplineSurface3D,
        source: BSplineSurface3D,
        uBreaks: [Double],
        vBreaks: [Double],
        tolerance: ModelingTolerance
    ) throws {
        let uSamples = samples(from: uBreaks)
        let vSamples = samples(from: vBreaks)
        var maximumResidual = 0.0
        for v in vSamples {
            for u in uSamples {
                let expected = try source.point(u: u, v: v, tolerance: tolerance)
                let actual = try result.point(u: u, v: v, tolerance: tolerance)
                maximumResidual = max(maximumResidual, (actual - expected).length.nextUp)
            }
        }
        guard maximumResidual <= tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: maximumResidual,
                tolerance: tolerance,
                message: "Rational B-spline trimmed surface failed exact-locus verification."
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

    private func breaks(
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
