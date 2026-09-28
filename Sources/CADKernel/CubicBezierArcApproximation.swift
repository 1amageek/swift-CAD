import Foundation
import CADCore

/// A circular arc as a cubic Bezier chain within the modeling distance of the circle: equal
/// spans with the standard 4/3·tan(θ/4) handles, the fewest spans (up to 64) that fit.
public struct CubicBezierArcApproximation: Sendable {
    public let tolerance: ModelingTolerance

    public init(tolerance: ModelingTolerance) {
        self.tolerance = tolerance
    }

    /// The arc about `center` of `radius` from `startAngle` turning by `sweep` (counterclockwise
    /// when positive), its ends exactly on the circle.
    public func chain(center: Point2D, radius: Double, startAngle: Double, sweep: Double) throws -> [Point2D] {
        guard radius.isFinite, radius > tolerance.distance, sweep.isFinite, abs(sweep) > 0,
              abs(sweep) <= 2 * .pi + tolerance.angle else {
            throw KernelError(phase: .validation, code: .invalidInput, tolerance: tolerance,
                              message: "An arc needs a positive radius and a sweep of at most one turn.")
        }
        func point(_ angle: Double) -> Point2D {
            Point2D(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
        }
        for segments in max(1, Int((abs(sweep) / (.pi / 2)).rounded(.up)))...64 {
            let step = sweep / Double(segments)
            let k = 4.0 / 3.0 * tan(step / 4) * radius
            var points = [point(startAngle)]
            var worst = 0.0
            for segment in 0..<segments {
                let from = startAngle + step * Double(segment), to = from + step
                let p0 = points[points.count - 1], p3 = point(to)
                let span = [
                    p0,
                    Point2D(x: p0.x - k * sin(from), y: p0.y + k * cos(from)),
                    Point2D(x: p3.x + k * sin(to), y: p3.y - k * cos(to)),
                    p3,
                ]
                for sample in 1...8 {
                    let t = Double(sample) / 9, s = 1 - t
                    let x = s * s * s * span[0].x + 3 * s * s * t * span[1].x + 3 * s * t * t * span[2].x + t * t * t * span[3].x
                    let y = s * s * s * span[0].y + 3 * s * s * t * span[1].y + 3 * s * t * t * span[2].y + t * t * t * span[3].y
                    worst = max(worst, abs(hypot(x - center.x, y - center.y) - radius))
                }
                points += span.dropFirst()
            }
            if worst <= tolerance.distance { return points }
        }
        throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                          message: "The arc did not fit the modeling distance in 64 spans.")
    }
}
