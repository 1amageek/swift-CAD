import Foundation
import CADCore
import CADGeometry
import CADIR

/// A four-sided surface interpolating its boundary and, along the v = 0 and v = 1 sides, exact
/// cross-boundary rows: the Boolean sum of a Hermite blend across v (cubic for tangent rows,
/// quintic with second-derivative rows) and the linear blend across u of the u = 0 and u = 1
/// sides, less their tensor product. With polynomial sides in a common basis per direction the sum
/// is one polynomial tensor B-spline: the Hermite functions' coefficients in the v basis are their
/// blossoms at its knots, and the linear blend's in the u basis are the Greville abscissae.
///
/// The surface takes `bottom` (v = 0) and `top` (v = 1) along u, `left` (u = 0) and `right`
/// (u = 1) along v; along a side with a plane its v-derivative rows leave (at v = 0) or enter (at
/// v = 1) that plane's face within it, so the surface is tangent continuous with the face, and with
/// curvature order its second-derivative rows lie in the plane too, so it is curvature
/// continuous. Where a row meets a left or right side it is that side's derivative, which must
/// therefore lie in the plane.
package struct ExactHermiteCoonsSurfaceBuilder {
    private let tolerance: ModelingTolerance
    private let resolver = DefaultBSplineCurveCommonBasisResolver()

    package init(tolerance: ModelingTolerance) {
        self.tolerance = tolerance
    }

    /// The surface, its continuous sides refined until a curved face's tangent planes are met
    /// within its allowance (a planar face is met at once, exactly).
    package func build(
        bottom: BSplineCurve3D, top: BSplineCurve3D, left: BSplineCurve3D, right: BSplineCurve3D,
        bottomPlane: ExactEdgeContinuitySupport?, topPlane: ExactEdgeContinuitySupport?,
        featureID: FeatureID
    ) throws -> BSplineSurface3D {
        let exact = [bottomPlane, topPlane].allSatisfy { $0?.isExact ?? true }
        var lastFailure: (any Error)?
        for level in 0...(exact ? 0 : 4) {
            let (surface, b0, b1) = try build(bottom: bottom, top: top, left: left, right: right,
                                              bottomPlane: bottomPlane, topPlane: topPlane, level: level, featureID: featureID)
            do {
                try bottomPlane?.certify(surface, boundaryV: 0, span: b0, tolerance: tolerance, featureID: featureID)
                try topPlane?.certify(surface, boundaryV: 1, span: b1, tolerance: tolerance, featureID: featureID)
                return surface
            } catch let error as KernelError where error.code == .classificationFailure || error.code == .resourceLimitExceeded {
                lastFailure = error
            }
        }
        throw failure(.classificationFailure,
            "A Square could not meet a curved face within its angular allowance: \(String(describing: lastFailure))", featureID)
    }

    private func build(
        bottom: BSplineCurve3D, top: BSplineCurve3D, left: BSplineCurve3D, right: BSplineCurve3D,
        bottomPlane: ExactEdgeContinuitySupport?, topPlane: ExactEdgeContinuitySupport?,
        level: Int, featureID: FeatureID
    ) throws -> (BSplineSurface3D, BSplineCurve3D, BSplineCurve3D) {
        try tolerance.validate()
        guard [bottom, top, left, right].allSatisfy({ $0.weights.allSatisfy { $0 == 1 } }) else {
            // FIXME(INCOMPLETE_IMPLEMENTATION): a rational side (an arc) makes the Boolean sum
            // rational with a product denominator, which this builder does not form, so continuity
            // along a Square with a rational side is refused. Production path:
            // SquareSurfaceFeatureEvaluator for every Square with a continuous side. Complete only
            // when rational sides are summed exactly, verified by a G1 Square with an arc side.
            throw failure(.unsupportedCapability, "A continuous Square's sides are polynomial curves.", featureID)
        }
        let order = [bottomPlane, topPlane].contains { $0?.order == .curvature } ? 2 : 1
        let degree = order == 2 ? 5 : 3
        let across = try resolver.resolve(first: bottom, second: top, tolerance: tolerance)
        var along = try resolver.resolve(first: left, second: right, tolerance: tolerance)
        if along.first.degree < degree {
            let bezier = BSplineCurve3D(degree: degree, knots: Array(repeating: 0, count: degree + 1) + Array(repeating: 1, count: degree + 1),
                                        controlPoints: Array(repeating: .origin, count: degree + 1))
            along = BSplineCurveCommonBasisPair(
                first: try resolver.resolve(first: along.first, second: bezier, tolerance: tolerance).first,
                second: try resolver.resolve(first: along.second, second: bezier, tolerance: tolerance).first
            )
        }
        let (b0, b1) = (try refined(across.first, level: level), try refined(across.second, level: level))
        let (a0, a1) = (along.first, along.second)
        for (side, along, sideAt, alongAt) in [(b0, a0, 0.0, 0.0), (b0, a1, 1.0, 0.0), (b1, a0, 0.0, 1.0), (b1, a1, 1.0, 1.0)] {
            guard (try point(side, sideAt) - point(along, alongAt)).length <= tolerance.distance else {
                throw failure(.invalidInput, "A Square's sides do not meet at its corners.", featureID)
            }
        }
        // The left and right sides' derivatives at both ends, first and (for curvature) second.
        func derivatives(_ curve: BSplineCurve3D, at t: Double) throws -> (Vector3D, Vector3D) {
            let geometry = try curve.differentialGeometry(at: t, tolerance: tolerance)
            return (geometry.firstDerivative, geometry.secondDerivative)
        }
        let (a0d0, a0s0) = try derivatives(a0, at: 0), (a0d1, a0s1) = try derivatives(a0, at: 1)
        let (a1d0, a1s0) = try derivatives(a1, at: 0), (a1d1, a1s1) = try derivatives(a1, at: 1)
        let greville = (0..<b0.controlPointCount).map { i in b0.knots[(i + 1)...(i + b0.degree)].reduce(0, +) / Double(b0.degree) }
        func linear(_ start: Vector3D, _ end: Vector3D) -> [Vector3D] { greville.map { start * (1 - $0) + end * $0 } }
        /// The v-derivative rows along a side: from its plane, leaving (or entering) it, ending on
        /// the left and right sides' derivatives; otherwise their linear blend.
        func firstRows(_ side: BSplineCurve3D, plane: ExactEdgeContinuitySupport?, start: Vector3D, end: Vector3D, entering: Bool) throws -> [Vector3D] {
            guard let plane else { return linear(start, end) }
            let directions = try plane.leavingDirections(along: side, tolerance: tolerance).map { $0 * (entering ? -1 : 1) }
            let sideEnds = (try point(side, 0), try point(side, 1))
            for (value, direction, at) in [(start, directions[0], sideEnds.0), (end, directions[directions.count - 1], sideEnds.1)] {
                let normal = try plane.normal(at: at, tolerance: tolerance)
                let slack = plane.isExact ? tolerance.angle : sin(plane.allowance)
                guard abs(value.dot(normal)) <= slack * value.length, value.dot(direction) > 0 else {
                    throw failure(.invalidInput,
                        "A Square's sides beside a continuous side must leave it within the face's plane.", featureID)
                }
            }
            let magnitude = plane.tension * 0.5 * (start.length + end.length)
            var rows = directions.map { $0 * magnitude }
            rows[0] = start
            rows[rows.count - 1] = end
            return rows
        }
        func secondRows(plane: ExactEdgeContinuitySupport?, side: BSplineCurve3D, start: Vector3D, end: Vector3D) throws -> [Vector3D] {
            guard let plane else { return linear(start, end) }
            let scale = max(start.length, end.length, 1)
            let (n0, n1) = (try plane.normal(at: try point(side, 0), tolerance: tolerance), try plane.normal(at: try point(side, 1), tolerance: tolerance))
            guard abs(start.dot(n0)) <= tolerance.angle * scale, abs(end.dot(n1)) <= tolerance.angle * scale else {
                throw failure(.invalidInput,
                    "A Square's sides beside a curvature-continuous side must not bend out of the face's plane there.", featureID)
            }
            var rows = Array(repeating: Vector3D.zero, count: greville.count)
            rows[0] = start
            rows[rows.count - 1] = end
            return rows
        }
        let d0 = try firstRows(b0, plane: bottomPlane, start: a0d0, end: a1d0, entering: false)
        let d1 = try firstRows(b1, plane: topPlane, start: a0d1, end: a1d1, entering: true)
        // The Hermite functions of v as Bézier coefficients on [0, 1], with the rows they weigh
        // along u and the values the left and right sides give them.
        var terms: [(bezier: [Double], rows: [Vector3D], left: Vector3D, right: Vector3D)] = []
        let vectors = { (curve: BSplineCurve3D) in curve.controlPoints.map { $0 - Point3D.origin } }
        if order == 1 {
            terms = [
                ([1, 1, 0, 0], vectors(b0), try point(a0, 0) - .origin, try point(a1, 0) - .origin),
                ([0, 0, 1, 1], vectors(b1), try point(a0, 1) - .origin, try point(a1, 1) - .origin),
                ([0, 1.0 / 3, 0, 0], d0, a0d0, a1d0),
                ([0, 0, -1.0 / 3, 0], d1, a0d1, a1d1),
            ]
        } else {
            let k0 = try secondRows(plane: bottomPlane, side: b0, start: a0s0, end: a1s0)
            let k1 = try secondRows(plane: topPlane, side: b1, start: a0s1, end: a1s1)
            terms = [
                ([1, 1, 1, 0, 0, 0], vectors(b0), try point(a0, 0) - .origin, try point(a1, 0) - .origin),
                ([0, 0, 0, 1, 1, 1], vectors(b1), try point(a0, 1) - .origin, try point(a1, 1) - .origin),
                ([0, 0.2, 0.4, 0, 0, 0], d0, a0d0, a1d0),
                ([0, 0, 0, -0.4, -0.2, 0], d1, a0d1, a1d1),
                ([0, 0, 0.05, 0, 0, 0], k0, a0s0, a1s0),
                ([0, 0, 0, 0.05, 0, 0], k1, a0s1, a1s1),
            ]
        }
        let vDegree = a0.degree
        let coefficients = terms.map { term in
            let elevated = elevate(term.bezier, to: vDegree)
            return (0..<a0.controlPointCount).map { j in blossom(elevated, Array(a0.knots[(j + 1)...(j + vDegree)])) }
        }
        let left = vectors(a0), right = vectors(a1)
        let rows = try (0..<a0.controlPointCount).map { j in
            try greville.indices.map { i -> Point3D in
                let u = greville[i]
                var value = left[j] * (1 - u) + right[j] * u
                for (k, term) in terms.enumerated() {
                    value = value + (term.rows[i] - (term.left * (1 - u) + term.right * u)) * coefficients[k][j]
                }
                try value.validate()
                return .origin + value
            }
        }
        let surface = BSplineSurface3D(uDegree: b0.degree, vDegree: vDegree, uKnots: b0.knots, vKnots: a0.knots, controlPoints: rows)
        try surface.validate(tolerance: tolerance)
        return (try ExactLoftSideSurfaceBuilder().validated(surface, tolerance: tolerance), b0, b1)
    }

    /// `curve` with the midpoint of every knot span inserted `level` times over.
    private func refined(_ curve: BSplineCurve3D, level: Int) throws -> BSplineCurve3D {
        var result = curve
        for _ in 0..<level {
            var distinct: [Double] = []
            for knot in result.knots where distinct.last.map({ knot > $0 }) ?? true { distinct.append(knot) }
            for (lower, upper) in zip(distinct, distinct.dropFirst()) {
                result = try result.insertingKnot(0.5 * (lower + upper), tolerance: tolerance)
            }
        }
        return result
    }

    private func point(_ curve: BSplineCurve3D, _ t: Double) throws -> Point3D {
        try Curve3D.bSpline(curve).point(at: t, tolerance: tolerance)
    }

    /// `bezier`'s coefficients raised to `degree`.
    private func elevate(_ bezier: [Double], to degree: Int) -> [Double] {
        var values = bezier
        while values.count - 1 < degree {
            let n = values.count - 1
            values = (0...(n + 1)).map { i in
                let a = i > 0 ? Double(i) / Double(n + 1) * values[i - 1] : 0
                let b = i <= n ? (1 - Double(i) / Double(n + 1)) * values[i] : 0
                return a + b
            }
        }
        return values
    }

    /// The blossom of the Bézier polynomial `bezier` at `parameters`, one per degree.
    private func blossom(_ bezier: [Double], _ parameters: [Double]) -> Double {
        var values = bezier
        for t in parameters {
            values = (0..<(values.count - 1)).map { (1 - t) * values[$0] + t * values[$0 + 1] }
        }
        return values[0]
    }

    private func failure(_ code: KernelErrorCode, _ message: String, _ featureID: FeatureID) -> KernelError {
        KernelError(phase: .evaluation, code: code, featureID: featureID, tolerance: tolerance, message: message)
    }
}
