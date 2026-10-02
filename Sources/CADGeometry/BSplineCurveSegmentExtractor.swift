import CADCore

/// The exact piece of a (rational) B-spline curve between two of its parameters, as a clamped
/// B-spline of its own on that interval: both parameters inserted (Boehm's algorithm on the
/// homogeneous control points) until they are breaks of full continuity loss, then the control
/// points between them taken with their knots.
package struct BSplineCurveSegmentExtractor {
    package init() {}

    package func segment(of curve: BSplineCurve3D, from t0: Double, to t1: Double, tolerance: ModelingTolerance) throws -> BSplineCurve3D {
        let p = curve.degree
        guard let first = curve.knots.first, let last = curve.knots.last, first <= t0, t0 < t1, t1 <= last else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                              message: "A B-spline segment runs forward within its curve's domain.")
        }
        var knots = curve.knots
        var points = zip(curve.controlPoints, curve.weights).map { [$0.x * $1, $0.y * $1, $0.z * $1, $1] }
        func insert(_ u: Double) {
            // The span holding u: the last k with knots[k] <= u < knots[k + 1] among non-empty spans.
            var k = p
            while k + 1 < knots.count - p - 1, knots[k + 1] <= u { k += 1 }
            var inserted: [[Double]] = []
            inserted.reserveCapacity(points.count + 1)
            for i in 0...points.count {
                if i <= k - p {
                    inserted.append(points[i])
                } else if i > k {
                    inserted.append(points[i - 1])
                } else {
                    let alpha = (u - knots[i]) / (knots[i + p] - knots[i])
                    inserted.append((0..<4).map { (1 - alpha) * points[i - 1][$0] + alpha * points[i][$0] })
                }
            }
            points = inserted
            knots.insert(u, at: k + 1)
        }
        for u in [t0, t1] {
            let needed = (u == first || u == last) ? 0 : p - knots.filter { $0 == u }.count
            for _ in 0..<max(0, needed) { insert(u) }
        }
        // The control point at t0 follows the last p copies of it; the one at t1 precedes its first.
        guard let lastT0 = knots.lastIndex(of: t0), let firstT1 = knots.firstIndex(of: t1) else {
            throw KernelError(phase: .geometry, code: .classificationFailure, tolerance: tolerance,
                              message: "A B-spline segment lost its ends while inserting them.")
        }
        let start = lastT0 - p + 1
        let end = firstT1
        guard start >= 1, end - 1 < points.count, end - 1 >= start - 1 else {
            throw KernelError(phase: .geometry, code: .classificationFailure, tolerance: tolerance,
                              message: "A B-spline segment's control points could not be taken.")
        }
        let taken = Array(points[(start - 1)...(end - 1)])
        let segmentKnots = Array(repeating: t0, count: p + 1) + Array(knots[(lastT0 + 1)..<firstT1]) + Array(repeating: t1, count: p + 1)
        let result = BSplineCurve3D(
            degree: p, knots: segmentKnots,
            controlPoints: taken.map { Point3D(x: $0[0] / $0[3], y: $0[1] / $0[3], z: $0[2] / $0[3]) },
            weights: taken.map { $0[3] }
        )
        try result.validate(tolerance: tolerance)
        return result
    }
}
