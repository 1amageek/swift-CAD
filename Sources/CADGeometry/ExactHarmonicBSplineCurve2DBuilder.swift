import CADCore
import Foundation

package struct ExactHarmonicBSplineCurve2DBuilder {
    package init() {}

    package func build(
        center: Point2D,
        cosine: Point2D,
        sine: Point2D,
        startParameter: Double,
        endParameter: Double,
        maximumSpanCount: Int = 16,
        tolerance: ModelingTolerance
    ) throws -> BSplineCurve2D {
        try tolerance.validate()
        let values = [
            center.x, center.y,
            cosine.x, cosine.y,
            sine.x, sine.y,
            startParameter, endParameter,
        ]
        let parameterSpan = endParameter - startParameter
        guard values.allSatisfy(\.isFinite),
              abs(parameterSpan) > tolerance.angle,
              abs(parameterSpan) <= 2.0 * Double.pi + tolerance.angle else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                residual: parameterSpan,
                tolerance: tolerance,
                message: "Exact harmonic pcurve conversion requires a finite nondegenerate span no longer than one period."
            )
        }
        if parameterSpan < 0.0 {
            return try build(
                center: center,
                cosine: cosine,
                sine: sine,
                startParameter: endParameter,
                endParameter: startParameter,
                maximumSpanCount: maximumSpanCount,
                tolerance: tolerance
            ).reversed(tolerance: tolerance)
        }
        let rawSpanCount = ceil(abs(parameterSpan) / (Double.pi * 0.5))
        guard rawSpanCount.isFinite,
              rawSpanCount <= Double(maximumSpanCount),
              rawSpanCount <= Double(Int.max) else {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                residual: rawSpanCount,
                tolerance: tolerance,
                message: "Exact harmonic pcurve conversion exceeded its rational span budget."
            )
        }
        let spanCount = max(1, Int(rawSpanCount))
        var controlPoints: [Point2D] = []
        var weights: [Double] = []
        var knots = Array(repeating: startParameter, count: 3)
        controlPoints.reserveCapacity(spanCount * 2 + 1)
        weights.reserveCapacity(spanCount * 2 + 1)
        knots.reserveCapacity(spanCount * 2 + 4)

        for index in 0..<spanCount {
            let lower = startParameter
                + parameterSpan * Double(index) / Double(spanCount)
            let upper = startParameter
                + parameterSpan * Double(index + 1) / Double(spanCount)
            let middle = 0.5 * (lower + upper)
            let middleWeight = cos(0.5 * abs(upper - lower))
            guard middleWeight.isFinite,
                  middleWeight > Double.ulpOfOne else {
                throw KernelError(
                    phase: .geometry,
                    code: .singularSystem,
                    residual: middleWeight,
                    tolerance: tolerance,
                    message: "Exact harmonic pcurve conversion produced a non-positive rational weight."
                )
            }
            if index == 0 {
                controlPoints.append(point(
                    center: center,
                    cosine: cosine,
                    sine: sine,
                    parameter: lower,
                    radialScale: 1.0
                ))
                weights.append(1.0)
            }
            controlPoints.append(point(
                center: center,
                cosine: cosine,
                sine: sine,
                parameter: middle,
                radialScale: 1.0 / middleWeight
            ))
            weights.append(middleWeight)
            controlPoints.append(point(
                center: center,
                cosine: cosine,
                sine: sine,
                parameter: upper,
                radialScale: 1.0
            ))
            weights.append(1.0)
            if index + 1 < spanCount {
                knots.append(contentsOf: [upper, upper])
            }
        }
        knots.append(contentsOf: Array(repeating: endParameter, count: 3))
        let result = BSplineCurve2D(
            degree: 2,
            knots: knots,
            controlPoints: controlPoints,
            weights: weights
        )
        try result.validate(tolerance: tolerance)
        return result
    }

    private func point(
        center: Point2D,
        cosine: Point2D,
        sine: Point2D,
        parameter: Double,
        radialScale: Double
    ) -> Point2D {
        Point2D(
            x: center.x
                + radialScale * (
                    cosine.x * cos(parameter) + sine.x * sin(parameter)
                ),
            y: center.y
                + radialScale * (
                    cosine.y * cos(parameter) + sine.y * sin(parameter)
                )
        )
    }
}
