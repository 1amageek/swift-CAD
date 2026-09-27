import Foundation
import CADCore

/// The offset of a cubic Bezier chain, as a cubic Bezier chain.
public struct CubicBezierChainOffset: Sendable {
    public let tolerance: ModelingTolerance

    public init(tolerance: ModelingTolerance) {
        self.tolerance = tolerance
    }

    /// The chain `controlPoints` offset by `distance` to its left (its tangent turned a quarter
    /// turn counterclockwise; a negative distance offsets to the right), within the modeling
    /// distance of the exact offset.
    ///
    /// Each span's offset O(u) = B(u) + d·N(u) is fitted piecewise by cubic Hermite spans whose
    /// ends take O and its exact derivative O′ = B′ + d·N′; a piece whose eight interior samples
    /// stray from O by more than the modeling distance is halved. A span whose offset folds back
    /// (O′ turning against B′, where d·κ reaches 1), a span with no tangent, and a joint whose two
    /// spans' offsets do not meet (a corner, which needs gap fill) are `invalidInput`.
    public func offset(of controlPoints: [Point2D], distance: Double) throws -> [Point2D] {
        guard controlPoints.count >= 4, (controlPoints.count - 1).isMultiple(of: 3) else {
            throw invalid("A cubic Bezier chain needs 3n + 1 control points.")
        }
        guard controlPoints.allSatisfy({ $0.x.isFinite && $0.y.isFinite }), distance.isFinite else {
            throw invalid("An offset needs finite control points and a finite distance.")
        }
        var result: [Point2D] = []
        for span in 0..<((controlPoints.count - 1) / 3) {
            let p = Array(controlPoints[(3 * span)...(3 * span + 3)])
            var pieces: [Point2D] = []
            try fit(p, distance, 0, 1, depth: 0, into: &pieces)
            if let last = result.last {
                guard length(last, pieces[0]) <= tolerance.distance else {
                    throw invalid("The chain has a corner at joint \(span); its offsets need gap fill to meet.")
                }
                result += pieces.dropFirst()
            } else {
                result = pieces
            }
        }
        return result
    }

    private func fit(_ p: [Point2D], _ d: Double, _ a: Double, _ b: Double, depth: Int, into result: inout [Point2D]) throws {
        let (startPoint, startDerivative) = try offsetJet(p, d, a)
        let (endPoint, endDerivative) = try offsetJet(p, d, b)
        let h = (b - a) / 3
        let piece = [
            startPoint,
            Point2D(x: startPoint.x + startDerivative.x * h, y: startPoint.y + startDerivative.y * h),
            Point2D(x: endPoint.x - endDerivative.x * h, y: endPoint.y - endDerivative.y * h),
            endPoint,
        ]
        var worst = 0.0
        for sample in 1...8 {
            let t = Double(sample) / 9
            let exact = try offsetJet(p, d, a + (b - a) * t).point
            worst = max(worst, length(evaluate(piece, t), exact))
        }
        if worst > tolerance.distance {
            guard depth < 24 else { throw invalid("The offset did not converge to the modeling distance.") }
            let middle = (a + b) / 2
            try fit(p, d, a, middle, depth: depth + 1, into: &result)
            try fit(p, d, middle, b, depth: depth + 1, into: &result)
            return
        }
        if result.isEmpty { result.append(piece[0]) }
        result += piece.dropFirst()
    }

    /// O(u) and O′(u) of span `p` offset by `d`.
    private func offsetJet(_ p: [Point2D], _ d: Double, _ u: Double) throws -> (point: Point2D, derivative: Point2D) {
        let (value, first, second) = jet(p, u)
        let speed = (first.x * first.x + first.y * first.y).squareRoot()
        guard speed > tolerance.distance else { throw invalid("A span of the chain has no tangent to offset along.") }
        let tangent = Point2D(x: first.x / speed, y: first.y / speed)
        let along = tangent.x * second.x + tangent.y * second.y
        // T′ = (B″ − T (T·B″)) / |B′|, N = T turned a quarter counterclockwise, N′ likewise.
        let turning = Point2D(x: (second.x - tangent.x * along) / speed, y: (second.y - tangent.y * along) / speed)
        let normal = Point2D(x: -tangent.y, y: tangent.x)
        let normalDerivative = Point2D(x: -turning.y, y: turning.x)
        let derivative = Point2D(x: first.x + d * normalDerivative.x, y: first.y + d * normalDerivative.y)
        guard derivative.x * first.x + derivative.y * first.y > 0 else {
            throw invalid("The offset folds back where the distance reaches the curve's radius of curvature.")
        }
        return (Point2D(x: value.x + d * normal.x, y: value.y + d * normal.y), derivative)
    }

    private func jet(_ p: [Point2D], _ t: Double) -> (Point2D, Point2D, Point2D) {
        let s = 1 - t
        let value = Point2D(
            x: s * s * s * p[0].x + 3 * s * s * t * p[1].x + 3 * s * t * t * p[2].x + t * t * t * p[3].x,
            y: s * s * s * p[0].y + 3 * s * s * t * p[1].y + 3 * s * t * t * p[2].y + t * t * t * p[3].y
        )
        let first = Point2D(
            x: 3 * s * s * (p[1].x - p[0].x) + 6 * s * t * (p[2].x - p[1].x) + 3 * t * t * (p[3].x - p[2].x),
            y: 3 * s * s * (p[1].y - p[0].y) + 6 * s * t * (p[2].y - p[1].y) + 3 * t * t * (p[3].y - p[2].y)
        )
        let second = Point2D(
            x: 6 * s * (p[2].x - 2 * p[1].x + p[0].x) + 6 * t * (p[3].x - 2 * p[2].x + p[1].x),
            y: 6 * s * (p[2].y - 2 * p[1].y + p[0].y) + 6 * t * (p[3].y - 2 * p[2].y + p[1].y)
        )
        return (value, first, second)
    }

    private func evaluate(_ p: [Point2D], _ t: Double) -> Point2D {
        jet(p, t).0
    }

    private func length(_ a: Point2D, _ b: Point2D) -> Double {
        ((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)).squareRoot()
    }

    private func invalid(_ message: String) -> KernelError {
        KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance, message: message)
    }
}
