import Foundation
import CADCore

/// The joints of a cubic Bezier chain that split one cubic: two neighboring spans that are the
/// halves of a single cubic at some parameter can be one span without changing the curve.
public struct CubicBezierChainJoints: Sendable {
    public let tolerance: ModelingTolerance

    public init(tolerance: ModelingTolerance) {
        self.tolerance = tolerance
    }

    /// The single span that spans `k - 1` and `k` of the chain `controlPoints` are the halves of,
    /// or nil when they are not one cubic. The joint is control point `3k`.
    ///
    /// Halves of one cubic Q split at t meet with collinear handles whose lengths stand in the
    /// ratio t : 1 − t, so t is read from the joint's handles; Q's inner control points follow from
    /// the outer handles, and Q split at t by De Casteljau must give back all seven points within
    /// the modeling distance.
    public func mergedSpan(of controlPoints: [Point2D], atJoint k: Int) throws -> [Point2D]? {
        guard controlPoints.count >= 7, (controlPoints.count - 1).isMultiple(of: 3) else {
            throw invalid("A cubic Bezier chain with a joint needs 3n + 1 control points, n at least 2.")
        }
        let spanCount = (controlPoints.count - 1) / 3
        guard k >= 1, k < spanCount else {
            throw invalid("Joint \(k) is not between two spans of the chain.")
        }
        guard controlPoints.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else {
            throw invalid("A cubic Bezier chain needs finite control points.")
        }
        let p = Array(controlPoints[(3 * k - 3)...(3 * k + 3)])
        let incoming = length(p[3], p[2])
        let outgoing = length(p[4], p[3])
        guard incoming > tolerance.distance, outgoing > tolerance.distance else { return nil }
        let t = incoming / (incoming + outgoing)
        let q0 = p[0]
        let q1 = Point2D(x: p[0].x + (p[1].x - p[0].x) / t, y: p[0].y + (p[1].y - p[0].y) / t)
        let q2 = Point2D(x: p[6].x + (p[5].x - p[6].x) / (1 - t), y: p[6].y + (p[5].y - p[6].y) / (1 - t))
        let q3 = p[6]
        let halves = split([q0, q1, q2, q3], at: t)
        for (reproduced, original) in zip(halves, p) where length(reproduced, original) > tolerance.distance {
            return nil
        }
        return [q0, q1, q2, q3]
    }

    /// The seven control points of cubic `q` split at `t`: the left half's four and the right
    /// half's last three.
    private func split(_ q: [Point2D], at t: Double) -> [Point2D] {
        func lerp(_ a: Point2D, _ b: Point2D) -> Point2D {
            Point2D(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
        }
        let a = lerp(q[0], q[1]), b = lerp(q[1], q[2]), c = lerp(q[2], q[3])
        let d = lerp(a, b), e = lerp(b, c)
        let f = lerp(d, e)
        return [q[0], a, d, f, e, c, q[3]]
    }

    private func length(_ a: Point2D, _ b: Point2D) -> Double {
        ((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)).squareRoot()
    }

    private func invalid(_ message: String) -> KernelError {
        KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance, message: message)
    }
}
