import Foundation
import CADCore
import CADGeometry

/// Where a plane cuts a B-spline surface ruled across one parameter — of degree one there with
/// two rows of the same weights, so each ruling is a straight line from one row to the other.
/// Along each ruling the plane's signed distance changes linearly, so the cut is exact: with the
/// rows' homogeneous numerators `Q₀(s)`, `Q₁(s)`, their weight `W(s)` and the distances
/// `F₀ = n·Q₀ − c·W`, `F₁ = n·Q₁ − c·W`, the ruling meets the plane at `t = F₀ / (F₀ − F₁)` and
/// the cut is the rational curve `(F₀·Q₁ − F₁·Q₀) / ((F₀ − F₁)·W)` in the surface's own `s`.
/// Where a ruling runs parallel to the plane (`F₀ = F₁`) the cut goes off to infinity, so the
/// curve covers the run of knot spans around the requested point whose rulings stay steep to it.
/// The cut's trace on the ruled surface is exact too: `s` itself across, and the ruling's
/// `t₀ + (t₁ − t₀)·F₀ / (F₀ − F₁)` along, a rational curve over `F₀ − F₁` in the same `s`.
package struct RuledBSplinePlaneSection {
    /// The cut and its trace on the ruled surface, both parameterised by the surface's `s` over
    /// the same knots' range, so a trim of one is the same trim of the other.
    package struct Cut {
        package let curve: BSplineCurve3D
        package let pcurve: BSplineCurve2D
    }

    private let tolerance: ModelingTolerance

    package init(tolerance: ModelingTolerance) {
        self.tolerance = tolerance
    }

    /// The cut; nil when the surface is not ruled across one parameter, or `near` lies on no
    /// part of the cut the surface's rulings reach.
    package func section(of surface: BSplineSurface3D, by plane: Plane3D, near: Point3D) throws -> Cut? {
        // The ruled direction: v (two rows), or u (two columns), read as rows along s.
        let alongU: Bool
        let rows: [[Point3D]]
        let rowWeights: [[Double]]
        let sKnots: [Double]
        let degree: Int
        let across: (lower: Double, upper: Double)
        if surface.vDegree == 1, surface.controlPoints.count == 2, surface.vKnots.count == 4 {
            alongU = true
            rows = surface.controlPoints
            rowWeights = surface.weights
            sKnots = surface.uKnots
            degree = surface.uDegree
            across = (surface.vKnots[1], surface.vKnots[2])
        } else if surface.uDegree == 1, surface.controlPoints.allSatisfy({ $0.count == 2 }), surface.uKnots.count == 4 {
            alongU = false
            rows = [surface.controlPoints.map { $0[0] }, surface.controlPoints.map { $0[1] }]
            rowWeights = [surface.weights.map { $0[0] }, surface.weights.map { $0[1] }]
            sKnots = surface.vKnots
            degree = surface.vDegree
            across = (surface.uKnots[1], surface.uKnots[2])
        } else {
            return nil
        }
        guard rowWeights[0] == rowWeights[1], degree >= 1 else { return nil }
        let normal = try plane.normal.normalized(tolerance: tolerance.distance)
        let offset = normal.dot(plane.origin - .origin)
        // Each control's homogeneous row points and distances, packed as polynomial splines in s:
        // (Q₀), (Q₁), and (W, F₀, F₁).
        let weights = rowWeights[0]
        func spline(_ points: [Point3D]) -> BSplineCurve3D { BSplineCurve3D(degree: degree, knots: sKnots, controlPoints: points) }
        let first = spline(zip(rows[0], weights).map { .origin + ($0 - .origin) * $1 })
        let second = spline(zip(rows[1], weights).map { .origin + ($0 - .origin) * $1 })
        let scalars = spline(weights.indices.map { i in
            Point3D(x: weights[i], y: weights[i] * (normal.dot(rows[0][i] - .origin) - offset),
                    z: weights[i] * (normal.dot(rows[1][i] - .origin) - offset))
        })
        let (q0, breaks) = try bezierPieces(first)
        let (q1, _) = try bezierPieces(second)
        let (packed, _) = try bezierPieces(scalars)
        // The span whose cut, at its middle, passes nearest `near`.
        var home: Int?
        var nearest = Double.infinity
        for span in 0..<(breaks.count - 1) {
            let s = 0.5 * (breaks[span] + breaks[span + 1])
            func row(_ t: Double) throws -> Point3D {
                try surface.point(u: alongU ? s : t, v: alongU ? t : s, tolerance: tolerance)
            }
            let (a, b) = (try row(across.lower), try row(across.upper))
            let (f0, f1) = (normal.dot(a - .origin) - offset, normal.dot(b - .origin) - offset)
            guard abs(f0 - f1) > tolerance.distance * 1e-3 else { continue }
            let cut = a + (b - a) * (f0 / (f0 - f1))
            if (cut - near).length < nearest { (home, nearest) = (span, (cut - near).length) }
        }
        guard let home else { return nil }
        /// A span's pieces of the cut, split until every Bernstein coefficient of both denominators
        /// has one sign; nil where a ruling there runs parallel to the plane.
        struct Piece {
            let lower: Double
            let upper: Double
            let numerator: [Vector3D]
            let denominator: [Double]
            /// The trace's numerators (across, along) and denominator `F₀ − F₁`, of degree p + 1.
            let traceAcross: [Double]
            let traceAlong: [Double]
            let traceDenominator: [Double]
        }
        func pieces(_ span: Int) -> [Piece]? {
            var pending: [(lower: Double, upper: Double, q0: [Vector3D], q1: [Vector3D], w: [Double], f0: [Double], f1: [Double], depth: Int)] = [
                (breaks[span], breaks[span + 1], q0[span].map { $0 - .origin }, q1[span].map { $0 - .origin },
                 packed[span].map(\.x), packed[span].map(\.y), packed[span].map(\.z), 0),
            ]
            var result: [Piece] = []
            while let piece = pending.popLast() {
                let difference = zip(piece.f0, piece.f1).map { $0 - $1 }
                let denominator = product(piece.w, difference)
                let sign = denominator.allSatisfy({ $0 > 0 }) && difference.allSatisfy({ $0 > 0 }) ? 1.0
                    : denominator.allSatisfy({ $0 < 0 }) && difference.allSatisfy({ $0 < 0 }) ? -1.0 : 0.0
                if sign == 0 {
                    guard piece.depth < 6 else { return nil }
                    let middle = 0.5 * (piece.lower + piece.upper)
                    let (q0a, q0b) = split(piece.q0), (q1a, q1b) = split(piece.q1)
                    let (wa, wb) = split(piece.w), (f0a, f0b) = split(piece.f0), (f1a, f1b) = split(piece.f1)
                    pending.append((middle, piece.upper, q0b, q1b, wb, f0b, f1b, piece.depth + 1))
                    pending.append((piece.lower, middle, q0a, q1a, wa, f0a, f1a, piece.depth + 1))
                    continue
                }
                // (F₀·Q₁ − F₁·Q₀) and (F₀ − F₁)·W, of degree 2p.
                let numerator = zip(product(piece.f0, piece.q1), product(piece.f1, piece.q0)).map { $0 - $1 }.map { $0 * sign }
                // (s·(F₀ − F₁), t₀·(F₀ − F₁) + (t₁ − t₀)·F₀) over (F₀ − F₁), raised to degree p + 1.
                let signed = difference.map { $0 * sign }
                let along = zip(signed, piece.f0).map { across.lower * $0 + (across.upper - across.lower) * $1 * sign }
                result.append(Piece(lower: piece.lower, upper: piece.upper, numerator: numerator, denominator: denominator.map { $0 * sign },
                                    traceAcross: product([piece.lower, piece.upper], signed),
                                    traceAlong: product([1, 1], along),
                                    traceDenominator: product([1, 1], signed)))
            }
            return result
        }
        guard let homePieces = pieces(home) else { return nil }
        // The run stops before rulings turn within a hundredth of the home span's angle to the
        // plane, where the cut runs far off and its weights fall toward zero.
        let scale = homePieces.flatMap(\.denominator).max() ?? 0
        func steep(_ more: [Piece]) -> Bool { more.allSatisfy { $0.denominator.min() ?? 0 > 0.01 * scale } }
        var run = homePieces
        var lower = home - 1
        while lower >= 0, let more = pieces(lower), steep(more) { run = more + run; lower -= 1 }
        var upper = home + 1
        while upper < breaks.count - 1, let more = pieces(upper), steep(more) { run += more; upper += 1 }
        // The pieces joined into one curve in s, a full-multiplicity knot at each join; neighbouring
        // pieces share their end, so the start of each later piece is dropped.
        let curveDegree = 2 * degree
        var knots = Array(repeating: run[0].lower, count: curveDegree + 1)
        var points: [Point3D] = []
        var curveWeights: [Double] = []
        for (index, piece) in run.enumerated() {
            for (j, value) in zip(piece.numerator, piece.denominator).enumerated() where index == 0 || j > 0 {
                points.append(.origin + value.0 * (1 / value.1))
                curveWeights.append(value.1)
            }
            knots += Array(repeating: piece.upper, count: index == run.count - 1 ? curveDegree + 1 : curveDegree)
        }
        let curve = BSplineCurve3D(degree: curveDegree, knots: knots, controlPoints: points, weights: curveWeights)
        try curve.validate(tolerance: tolerance)
        let traceDegree = degree + 1
        var traceKnots = Array(repeating: run[0].lower, count: traceDegree + 1)
        var tracePoints: [Point2D] = []
        var traceWeights: [Double] = []
        for (index, piece) in run.enumerated() {
            for j in piece.traceDenominator.indices where index == 0 || j > 0 {
                let (across, along, weight) = (piece.traceAcross[j], piece.traceAlong[j], piece.traceDenominator[j])
                tracePoints.append(alongU ? Point2D(x: across / weight, y: along / weight) : Point2D(x: along / weight, y: across / weight))
                traceWeights.append(weight)
            }
            traceKnots += Array(repeating: piece.upper, count: index == run.count - 1 ? traceDegree + 1 : traceDegree)
        }
        return Cut(curve: curve, pcurve: BSplineCurve2D(degree: traceDegree, knots: traceKnots, controlPoints: tracePoints, weights: traceWeights))
    }

    // MARK: - Bernstein arithmetic

    /// A polynomial spline's Bézier control points per knot span, with the spans' breaks.
    private func bezierPieces(_ curve: BSplineCurve3D) throws -> ([[Point3D]], [Double]) {
        var result = curve
        var breaks: [Double] = []
        for knot in curve.knots where breaks.last.map({ knot > $0 }) ?? true { breaks.append(knot) }
        for knot in breaks.dropFirst().dropLast() {
            while result.knots.filter({ $0 == knot }).count < curve.degree {
                result = try result.insertingKnot(knot, tolerance: tolerance)
            }
        }
        let p = curve.degree
        let pieces = (0..<(breaks.count - 1)).map { span in Array(result.controlPoints[(span * p)...(span * p + p)]) }
        return (pieces, breaks)
    }

    private func binomial(_ n: Int, _ k: Int) -> Double {
        var value = 1.0
        for i in 0..<k { value = value * Double(n - i) / Double(i + 1) }
        return value
    }

    /// The Bernstein coefficients of the product of two Bernstein polynomials.
    private func product(_ a: [Double], _ b: [Double]) -> [Double] {
        let (m, n) = (a.count - 1, b.count - 1)
        var result = Array(repeating: 0.0, count: m + n + 1)
        for i in 0...m {
            for j in 0...n { result[i + j] += binomial(m, i) * binomial(n, j) / binomial(m + n, i + j) * a[i] * b[j] }
        }
        return result
    }

    private func product(_ a: [Double], _ b: [Vector3D]) -> [Vector3D] {
        let (m, n) = (a.count - 1, b.count - 1)
        var result = Array(repeating: Vector3D.zero, count: m + n + 1)
        for i in 0...m {
            for j in 0...n { result[i + j] = result[i + j] + b[j] * (binomial(m, i) * binomial(n, j) / binomial(m + n, i + j) * a[i]) }
        }
        return result
    }

    /// De Casteljau's halves of a Bernstein polynomial.
    private func split(_ a: [Double]) -> ([Double], [Double]) {
        var rows = [a]
        while rows[rows.count - 1].count > 1 {
            let last = rows[rows.count - 1]
            rows.append((0..<(last.count - 1)).map { 0.5 * (last[$0] + last[$0 + 1]) })
        }
        return (rows.map { $0[0] }, rows.reversed().map { $0[$0.count - 1] })
    }

    private func split(_ a: [Vector3D]) -> ([Vector3D], [Vector3D]) {
        var rows = [a]
        while rows[rows.count - 1].count > 1 {
            let last = rows[rows.count - 1]
            rows.append((0..<(last.count - 1)).map { (last[$0] + last[$0 + 1]) * 0.5 })
        }
        return (rows.map { $0[0] }, rows.reversed().map { $0[$0.count - 1] })
    }
}
