import Foundation
import CADCore

/// Extensions of a cubic Bezier chain past one of its ends.
public struct CubicBezierChainExtension: Sendable {
    /// Which end of the chain is extended.
    public enum End: Sendable {
        case start
        case end
    }

    public let tolerance: ModelingTolerance

    public init(tolerance: ModelingTolerance) {
        self.tolerance = tolerance
    }

    /// The Natural extension at `end`: the end span's own cubic continued past the end until it
    /// has run `length` along itself, as one new span. Returns the span's three new control
    /// points in chain order: to append after the end, or to prepend before the start.
    ///
    /// The end span B on [0, 1] continues as the same polynomial on [1, s]; that piece's control
    /// points are the blossom values f(1,1,1), f(1,1,s), f(1,s,s), f(s,s,s). s solves
    /// ∫₁ˢ |B′(u)| du = length by Newton steps on the arc length, integrated by composite
    /// five-point Gauss–Legendre.
    public func naturalSpan(of controlPoints: [Point2D], at end: End, length: Double) throws -> [Point2D] {
        guard controlPoints.count >= 4, (controlPoints.count - 1).isMultiple(of: 3) else {
            throw invalid("A cubic Bezier chain needs 3n + 1 control points.")
        }
        guard controlPoints.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else {
            throw invalid("A cubic Bezier chain needs finite control points.")
        }
        guard length.isFinite, length > tolerance.distance else {
            throw invalid("An extension length must be finite and above the modeling distance.")
        }
        let count = controlPoints.count
        let span: [Point2D] = switch end {
        case .end: Array(controlPoints[(count - 4)...])
        case .start: Array(controlPoints[0...3].reversed())
        }
        let endSpeed = speed(span, at: 1)
        guard endSpeed > tolerance.distance else {
            throw invalid("The chain's end has no tangent to continue along.")
        }
        var s = 1 + length / endSpeed
        for _ in 0..<50 {
            let error = arcLength(span, from: 1, to: s) - length
            let step = error / speed(span, at: s)
            guard step.isFinite else { throw invalid("The Natural extension did not converge.") }
            s -= step
            if abs(step) <= 1e-14 * max(1, s) { break }
        }
        guard s > 1, abs(arcLength(span, from: 1, to: s) - length) <= tolerance.distance else {
            throw invalid("The Natural extension did not reach the requested length.")
        }
        let continued = [blossom(span, 1, 1, s), blossom(span, 1, s, s), blossom(span, s, s, s)]
        return switch end {
        case .end: continued
        case .start: continued.reversed()
        }
    }

    /// The blossom of cubic `p` at (u1, u2, u3): De Casteljau with a different parameter per level.
    private func blossom(_ p: [Point2D], _ u1: Double, _ u2: Double, _ u3: Double) -> Point2D {
        func level(_ points: [Point2D], _ u: Double) -> [Point2D] {
            zip(points, points.dropFirst()).map { a, b in Point2D(x: a.x + (b.x - a.x) * u, y: a.y + (b.y - a.y) * u) }
        }
        return level(level(level(p, u1), u2), u3)[0]
    }

    /// |B′(u)| of cubic `p`, for any u.
    private func speed(_ p: [Point2D], at u: Double) -> Double {
        let v = 1 - u
        let a = 3 * v * v, b = 6 * v * u, c = 3 * u * u
        let x = a * (p[1].x - p[0].x) + b * (p[2].x - p[1].x) + c * (p[3].x - p[2].x)
        let y = a * (p[1].y - p[0].y) + b * (p[2].y - p[1].y) + c * (p[3].y - p[2].y)
        return (x * x + y * y).squareRoot()
    }

    private func arcLength(_ p: [Point2D], from a: Double, to b: Double) -> Double {
        let nodes = [0.0, -0.538_469_310_105_683_1, 0.538_469_310_105_683_1, -0.906_179_845_938_664, 0.906_179_845_938_664]
        let weights = [0.568_888_888_888_888_9, 0.478_628_670_499_366_5, 0.478_628_670_499_366_5, 0.236_926_885_056_189_1, 0.236_926_885_056_189_1]
        let pieces = 16
        let width = (b - a) / Double(pieces)
        var total = 0.0
        for piece in 0..<pieces {
            let middle = a + (Double(piece) + 0.5) * width
            for (node, weight) in zip(nodes, weights) {
                total += weight * speed(p, at: middle + node * width / 2)
            }
        }
        return total * width / 2
    }

    private func invalid(_ message: String) -> KernelError {
        KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance, message: message)
    }
}
