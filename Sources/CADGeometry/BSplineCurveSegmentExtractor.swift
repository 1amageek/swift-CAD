import CADCore

/// The exact piece of a (rational) B-spline curve between two of its parameters, as a clamped
/// B-spline of its own on that interval: both parameters inserted (Boehm's algorithm on the
/// homogeneous control points) until they are breaks of full continuity loss, then the control
/// points between them taken with their knots.
package struct BSplineCurveSegmentExtractor {
    package init() {}

    package func segment<A: ExactScalarAdmission & ~Copyable>(of curve: BSplineCurve3D, from t0: Double, to t1: Double, tolerance: ModelingTolerance, using execution: inout A) throws -> BSplineCurve3D {
        try execution.consumeWork(1)
        let p = curve.degree
        guard let first = curve.knots.first, let last = curve.knots.last, first <= t0, t0 < t1, t1 <= last else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                              message: "A B-spline segment runs forward within its curve's domain.")
        }
        var knots = curve.knots
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: curve.controlPoints.count, of: [Double].self))
        var points = try zip(curve.controlPoints, curve.weights).map { point, weight in
            try execution.consumeWork(1)
            try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 4, of: Double.self))
            return [point.x * weight, point.y * weight, point.z * weight, weight]
        }
        func insert(_ u: Double, using execution: inout A) throws {
            try execution.consumeWork(1)
            // The span holding u: the last k with knots[k] <= u < knots[k + 1] among non-empty spans.
            var k = p
            while k + 1 < knots.count - p - 1, knots[k + 1] <= u { try execution.consumeWork(1); k += 1 }
            var inserted: [[Double]] = []
            let capacity = points.count.addingReportingOverflow(1)
            guard !capacity.overflow else { throw ExactScalarFailure.countOverflow }
            try execution.retainStorage(bytes: exactScalarPayloadBytes(count: capacity.partialValue, of: [Double].self))
            inserted.reserveCapacity(capacity.partialValue)
            for i in 0...points.count {
                try execution.consumeWork(1)
                if i <= k - p {
                    inserted.append(points[i])
                } else if i > k {
                    inserted.append(points[i - 1])
                } else {
                    let alpha = (u - knots[i]) / (knots[i + p] - knots[i])
                    try execution.retainStorage(bytes: exactScalarPayloadBytes(count: 4, of: Double.self))
                    inserted.append(try (0..<4).map { try execution.consumeWork(1); return (1 - alpha) * points[i - 1][$0] + alpha * points[i][$0] })
                }
            }
            points = inserted
            let knotCapacity = knots.count.addingReportingOverflow(1)
            guard !knotCapacity.overflow else { throw ExactScalarFailure.countOverflow }
            try execution.retainStorage(bytes: exactScalarPayloadBytes(count: knotCapacity.partialValue, of: Double.self))
            for _ in knots { try execution.consumeWork(1) }
            knots.reserveCapacity(knotCapacity.partialValue)
            knots.insert(u, at: k + 1)
        }
        for boundary in 0..<2 {
            let u = boundary == 0 ? t0 : t1
            let needed: Int
            if u == first || u == last { needed = 0 }
            else {
                let multiplicity = try knots.reduce(0) { try execution.consumeWork(1); return $0 + ($1 == u ? 1 : 0) }
                needed = p - multiplicity
            }
            for _ in 0..<max(0, needed) { try insert(u, using: &execution) }
        }
        // The control point at t0 follows the last p copies of it; the one at t1 precedes its first.
        guard let lastT0 = try knots.lastIndex(where: { try execution.consumeWork(1); return $0 == t0 }), let firstT1 = try knots.firstIndex(where: { try execution.consumeWork(1); return $0 == t1 }) else {
            throw KernelError(phase: .geometry, code: .classificationFailure, tolerance: tolerance,
                              message: "A B-spline segment lost its ends while inserting them.")
        }
        let start = lastT0 - p + 1
        let end = firstT1
        guard start >= 1, end - 1 < points.count, end - 1 >= start - 1 else {
            throw KernelError(phase: .geometry, code: .classificationFailure, tolerance: tolerance,
                              message: "A B-spline segment's control points could not be taken.")
        }
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: end - start + 1, of: [Double].self))
        let taken = Array(points[(start - 1)...(end - 1)])
        let endpoint = p.addingReportingOverflow(1)
        let doubled = endpoint.partialValue.multipliedReportingOverflow(by: 2)
        let interior = firstT1 - lastT0 - 1
        let total = doubled.partialValue.addingReportingOverflow(interior)
        guard !endpoint.overflow, !doubled.overflow, !total.overflow else { throw ExactScalarFailure.countOverflow }
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: total.partialValue, of: Double.self))
        var segmentKnots: [Double] = []
        segmentKnots.reserveCapacity(total.partialValue)
        for _ in 0..<endpoint.partialValue { try execution.consumeWork(1); segmentKnots.append(t0) }
        for knot in knots[(lastT0 + 1)..<firstT1] { try execution.consumeWork(1); segmentKnots.append(knot) }
        for _ in 0..<endpoint.partialValue { try execution.consumeWork(1); segmentKnots.append(t1) }
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: taken.count, of: Point3D.self))
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: taken.count, of: Double.self))
        let result = BSplineCurve3D(
            degree: p, knots: segmentKnots,
            controlPoints: try taken.map { try execution.consumeWork(1); return Point3D(x: $0[0] / $0[3], y: $0[1] / $0[3], z: $0[2] / $0[3]) },
            weights: try taken.map { try execution.consumeWork(1); return $0[3] }
        )
        try result.validate(tolerance: tolerance, using: &execution)
        return result
    }
}
