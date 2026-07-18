import Foundation
import CADCore
import CADGeometry

struct ExactHarmonicArcBSplineBuilder {
    let tolerance: ModelingTolerance

    func build(
        center: Point2D,
        cosine: Point2D,
        sine: Point2D,
        startParameter: Double,
        endParameter: Double
    ) throws -> BSplineCurve2D {
        try tolerance.validate()
        let values = [
            center.x,
            center.y,
            cosine.x,
            cosine.y,
            sine.x,
            sine.y,
            startParameter,
            endParameter,
        ]
        guard values.allSatisfy(\.isFinite) else {
            throw invalid("Exact harmonic arc conversion requires finite inputs.")
        }

        let span = endParameter - startParameter
        guard abs(span) > tolerance.angle,
              abs(span) <= 2.0 * Double.pi + tolerance.angle else {
            throw invalid("Exact harmonic arc conversion requires a nonzero span of at most one period.")
        }

        let cosineLength = hypot(cosine.x, cosine.y)
        let sineLength = hypot(sine.x, sine.y)
        let basisScale = cosineLength * sineLength
        let determinant = cosine.x * sine.y - cosine.y * sine.x
        guard cosineLength > Double.ulpOfOne,
              sineLength > Double.ulpOfOne,
              basisScale.isFinite,
              abs(determinant) > basisScale * tolerance.angle else {
            throw invalid("Exact harmonic arc conversion requires a nondegenerate parameter ellipse.")
        }

        let maximumSegmentSpan = 0.5 * Double.pi
        let segmentCount = max(1, Int(ceil(abs(span) / maximumSegmentSpan)))
        var controlPoints: [Point2D] = []
        var weights: [Double] = []
        controlPoints.reserveCapacity(segmentCount * 2 + 1)
        weights.reserveCapacity(segmentCount * 2 + 1)

        for segmentIndex in 0..<segmentCount {
            let lowerFraction = Double(segmentIndex) / Double(segmentCount)
            let upperFraction = Double(segmentIndex + 1) / Double(segmentCount)
            let lowerParameter = startParameter + span * lowerFraction
            let upperParameter = segmentIndex + 1 == segmentCount
                ? endParameter
                : startParameter + span * upperFraction
            let middleParameter = 0.5 * (lowerParameter + upperParameter)
            let halfSpan = 0.5 * (upperParameter - lowerParameter)
            let middleWeight = cos(halfSpan)
            guard middleWeight.isFinite,
                  middleWeight > Double.ulpOfOne else {
                throw invalid("Exact harmonic arc conversion produced a singular conic weight.")
            }

            if segmentIndex == 0 {
                controlPoints.append(point(
                    center: center,
                    cosine: cosine,
                    sine: sine,
                    parameter: lowerParameter
                ))
                weights.append(1.0)
            }
            controlPoints.append(Point2D(
                x: center.x + (
                    cosine.x * cos(middleParameter)
                        + sine.x * sin(middleParameter)
                ) / middleWeight,
                y: center.y + (
                    cosine.y * cos(middleParameter)
                        + sine.y * sin(middleParameter)
                ) / middleWeight
            ))
            weights.append(middleWeight)
            controlPoints.append(point(
                center: center,
                cosine: cosine,
                sine: sine,
                parameter: upperParameter
            ))
            weights.append(1.0)
        }

        var knots = Array(repeating: 0.0, count: 3)
        if segmentCount > 1 {
            for boundary in 1..<segmentCount {
                knots.append(Double(boundary))
                knots.append(Double(boundary))
            }
        }
        knots.append(contentsOf: Array(repeating: Double(segmentCount), count: 3))

        let curve = BSplineCurve2D(
            degree: 2,
            knots: knots,
            controlPoints: controlPoints,
            weights: weights
        )
        try curve.validate(tolerance: tolerance)
        return curve
    }

    private func point(
        center: Point2D,
        cosine: Point2D,
        sine: Point2D,
        parameter: Double
    ) -> Point2D {
        Point2D(
            x: center.x + cosine.x * cos(parameter) + sine.x * sin(parameter),
            y: center.y + cosine.y * cos(parameter) + sine.y * sin(parameter)
        )
    }

    private func invalid(_ message: String) -> KernelError {
        KernelError(
            phase: .exchange,
            code: .invalidInput,
            tolerance: tolerance,
            message: message
        )
    }
}
