import Foundation
import CADCore
import CADGeometry

struct ExactPolylineBSplineBuilder {
    let tolerance: ModelingTolerance

    func build(points: [SurfaceParameter]) throws -> BSplineCurve2D {
        try tolerance.validate()
        guard points.count >= 2 else {
            throw exchangeError("Exact polyline p-curves require at least two points.")
        }
        var controlPoints: [Point2D] = []
        controlPoints.reserveCapacity(points.count)
        for (index, point) in points.enumerated() {
            try point.validate()
            if index > 0 {
                let previous = points[index - 1]
                guard hypot(point.u - previous.u, point.v - previous.v) > Double.ulpOfOne else {
                    throw exchangeError("Exact polyline p-curves cannot contain a zero-length segment.")
                }
            }
            controlPoints.append(Point2D(x: point.u, y: point.v))
        }

        let upper = Double(controlPoints.count - 1)
        var knots = [0.0, 0.0]
        if controlPoints.count > 2 {
            knots.append(contentsOf: (1..<(controlPoints.count - 1)).map(Double.init))
        }
        knots.append(contentsOf: [upper, upper])
        let curve = BSplineCurve2D(
            degree: 1,
            knots: knots,
            controlPoints: controlPoints
        )
        try curve.validate(tolerance: tolerance)
        return curve
    }

    private func exchangeError(_ message: String) -> KernelError {
        KernelError(
            phase: .exchange,
            code: .invalidInput,
            tolerance: tolerance,
            message: message
        )
    }
}
