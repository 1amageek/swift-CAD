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
            "A surface could not meet a curved face within its allowances: \(String(describing: lastFailure))", featureID)
    }

    private func build(
        bottom: BSplineCurve3D, top: BSplineCurve3D, left: BSplineCurve3D, right: BSplineCurve3D,
        bottomPlane: ExactEdgeContinuitySupport?, topPlane: ExactEdgeContinuitySupport?,
        level: Int, featureID: FeatureID
    ) throws -> (BSplineSurface3D, BSplineCurve3D, BSplineCurve3D) {
        try tolerance.validate()
        // Rational sides (arcs) make the sum rational over the product of their weight functions
        // (`ExactRationalBooleanSum`); polynomial ones keep one polynomial tensor.
        let rational = [bottom, top, left, right].contains { $0.weights.contains { $0 != 1 } }
        let order = [bottomPlane, topPlane].contains { $0?.order == .curvature } ? 2 : 1
        let degree = order == 2 ? 5 : 3
        let across = try resolver.resolve(first: bottom, second: top, tolerance: tolerance)
        var along = try resolver.resolve(first: left, second: right, tolerance: tolerance)
        if rational == false, along.first.degree < degree {
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
                throw failure(.invalidInput, "A surface's sides do not meet at its corners.", featureID)
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
                        "The sides beside a continuous side must leave it within the face's plane.", featureID)
                }
            }
            let magnitude = plane.tension * 0.5 * (start.length + end.length)
            var rows = directions.map { $0 * magnitude }
            rows[0] = start
            rows[rows.count - 1] = end
            return rows
        }
        func secondRows(plane: ExactEdgeContinuitySupport?, side: BSplineCurve3D, firstRows: [Vector3D],
                        start: Vector3D, end: Vector3D) throws -> [Vector3D] {
            guard let plane else { return linear(start, end) }
            if plane.isExact {
                let scale = max(start.length, end.length, 1)
                let (n0, n1) = (try plane.normal(at: try point(side, 0), tolerance: tolerance), try plane.normal(at: try point(side, 1), tolerance: tolerance))
                guard abs(start.dot(n0)) <= tolerance.angle * scale, abs(end.dot(n1)) <= tolerance.angle * scale else {
                    throw failure(.invalidInput,
                        "The sides beside a curvature-continuous side must not bend out of the face's plane there.", featureID)
                }
            }
            // Beside a curved face the rows take its normal curvature across the edge; the sides'
            // own second derivatives end them, certified with the surface.
            var rows = try plane.curvatureRows(along: side, rows: firstRows, tolerance: tolerance)
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
            let k0 = try secondRows(plane: bottomPlane, side: b0, firstRows: d0, start: a0s0, end: a1s0)
            let k1 = try secondRows(plane: topPlane, side: b1, firstRows: d1, start: a0s1, end: a1s1)
            terms = [
                ([1, 1, 1, 0, 0, 0], vectors(b0), try point(a0, 0) - .origin, try point(a1, 0) - .origin),
                ([0, 0, 0, 1, 1, 1], vectors(b1), try point(a0, 1) - .origin, try point(a1, 1) - .origin),
                ([0, 0.2, 0.4, 0, 0, 0], d0, a0d0, a1d0),
                ([0, 0, 0, -0.4, -0.2, 0], d1, a0d1, a1d1),
                ([0, 0, 0.05, 0, 0, 0], k0, a0s0, a1s0),
                ([0, 0, 0, 0.05, 0, 0], k1, a0s1, a1s1),
            ]
        }
        if rational {
            let surface = try rationalSum(terms: terms, b0: b0, b1: b1, a0: a0, a1: a1)
            try surface.validate(tolerance: tolerance)
            return (try ExactLoftSideSurfaceBuilder().validated(surface, tolerance: tolerance), b0, b1)
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

    /// The surface continuous along neighbouring sides too: the Boolean sum of the Hermite blends
    /// across v (between bottom and top with their rows) and across u (between left and right with
    /// theirs), less the tensor of the corners' jets. The blends are cubic at tangent order and
    /// quintic, with second-derivative rows, when any side is curvature continuous. Rows meet at
    /// the corners on the sides' derivatives, and the rows and columns through a corner take one
    /// set of mixed derivatives there: the mean of their natural ones, the twist kept in the
    /// corner's tangent plane and, beside a planar face, the higher ones too. Planar faces meeting
    /// at a corner must be one plane, and curved faces are certified within their allowances, the
    /// sides refined until they are.
    package func buildAllSides(
        bottom: BSplineCurve3D, top: BSplineCurve3D, left: BSplineCurve3D, right: BSplineCurve3D,
        bottomSupport: ExactEdgeContinuitySupport?, topSupport: ExactEdgeContinuitySupport?,
        leftSupport: ExactEdgeContinuitySupport?, rightSupport: ExactEdgeContinuitySupport?,
        featureID: FeatureID
    ) throws -> BSplineSurface3D {
        let supports = [bottomSupport, topSupport, leftSupport, rightSupport]
        let exact = supports.allSatisfy { $0?.isExact ?? true }
        var lastFailure: (any Error)?
        for level in 0...(exact ? 0 : 4) {
            let (surface, curves) = try allSides(bottom: bottom, top: top, left: left, right: right,
                                                 supports: supports, level: level, featureID: featureID)
            do {
                try bottomSupport?.certify(surface, along: .v(0), span: curves[0], tolerance: tolerance, featureID: featureID)
                try topSupport?.certify(surface, along: .v(1), span: curves[1], tolerance: tolerance, featureID: featureID)
                try leftSupport?.certify(surface, along: .u(0), span: curves[2], tolerance: tolerance, featureID: featureID)
                try rightSupport?.certify(surface, along: .u(1), span: curves[3], tolerance: tolerance, featureID: featureID)
                return surface
            } catch let error as KernelError where error.code == .classificationFailure || error.code == .resourceLimitExceeded {
                lastFailure = error
            }
        }
        throw failure(.classificationFailure,
            "A surface could not meet its curved faces within their allowances: \(String(describing: lastFailure))", featureID)
    }

    private func allSides(
        bottom: BSplineCurve3D, top: BSplineCurve3D, left: BSplineCurve3D, right: BSplineCurve3D,
        supports: [ExactEdgeContinuitySupport?], level: Int, featureID: FeatureID
    ) throws -> (BSplineSurface3D, [BSplineCurve3D]) {
        try tolerance.validate()
        // Order 1 blends cubic Hermite functions (positions and first derivatives); order 2 quintic
        // ones, adding second derivatives.
        let order = supports.contains { $0?.order == .curvature } ? 2 : 1
        let degree = 2 * order + 1
        let bezier = BSplineCurve3D(degree: degree, knots: Array(repeating: 0, count: degree + 1) + Array(repeating: 1, count: degree + 1),
                                    controlPoints: Array(repeating: .origin, count: degree + 1))
        func commonPair(_ first: BSplineCurve3D, _ second: BSplineCurve3D) throws -> (BSplineCurve3D, BSplineCurve3D) {
            var pair = try resolver.resolve(first: first, second: second, tolerance: tolerance)
            if pair.first.degree < degree {
                pair = BSplineCurveCommonBasisPair(
                    first: try resolver.resolve(first: pair.first, second: bezier, tolerance: tolerance).first,
                    second: try resolver.resolve(first: pair.second, second: bezier, tolerance: tolerance).first
                )
            }
            return (try refined(pair.first, level: level), try refined(pair.second, level: level))
        }
        // Bottom (v = 0) and top along u; left (u = 0) and right along v.
        let (b0, b1) = try commonPair(bottom, top)
        let (a0, a1) = try commonPair(left, right)
        for (side, along, sideAt, alongAt) in [(b0, a0, 0.0, 0.0), (b0, a1, 1.0, 0.0), (b1, a0, 0.0, 1.0), (b1, a1, 1.0, 1.0)] {
            guard (try point(side, sideAt) - point(along, alongAt)).length <= tolerance.distance else {
                throw failure(.invalidInput, "A surface's sides do not meet at its corners.", featureID)
            }
        }
        let alongU = [b0, b1], alongV = [a0, a1]
        // The corner jets: jet[cu][cv][j][k] is ∂ʲ⁺ᵏS/∂uʲ∂vᵏ at the corner (u, v) = (cu, cv). The
        // sides give the pure derivatives; the mixed ones are agreed below.
        var jet = Array(repeating: Array(repeating: Array(repeating: Array(repeating: Vector3D.zero, count: order + 1), count: order + 1), count: 2), count: 2)
        for cu in 0...1 {
            for cv in 0...1 {
                let u = try alongU[cv].differentialGeometry(at: Double(cu), tolerance: tolerance)
                let v = try alongV[cu].differentialGeometry(at: Double(cv), tolerance: tolerance)
                jet[cu][cv][0][0] = u.position - .origin
                jet[cu][cv][1][0] = u.firstDerivative
                jet[cu][cv][0][1] = v.firstDerivative
                if order == 2 {
                    jet[cu][cv][2][0] = u.secondDerivative
                    jet[cu][cv][0][2] = v.secondDerivative
                }
            }
        }
        func grevilles(_ curve: BSplineCurve3D) -> [Double] {
            (0..<curve.controlPointCount).map { i in curve.knots[(i + 1)...(i + curve.degree)].reduce(0, +) / Double(curve.degree) }
        }
        func linear(_ curve: BSplineCurve3D, _ start: Vector3D, _ end: Vector3D) -> [Vector3D] {
            grevilles(curve).map { start * (1 - $0) + end * $0 }
        }
        /// The first-derivative rows across a side from its support (ending on the given corner
        /// derivatives, which must leave the side within the face's tangent plane), or their linear
        /// blend.
        func firstRows(_ side: BSplineCurve3D, support: ExactEdgeContinuitySupport?, start: Vector3D, end: Vector3D, entering: Bool) throws -> [Vector3D] {
            guard let support else { return linear(side, start, end) }
            let directions = try support.leavingDirections(along: side, tolerance: tolerance).map { $0 * (entering ? -1 : 1) }
            let ends = (try point(side, 0), try point(side, 1))
            for (value, direction, at) in [(start, directions[0], ends.0), (end, directions[directions.count - 1], ends.1)] {
                let normal = try support.normal(at: at, tolerance: tolerance)
                let slack = support.isExact ? tolerance.angle : sin(support.allowance)
                guard abs(value.dot(normal)) <= slack * value.length, value.dot(direction) > 0 else {
                    throw failure(.invalidInput,
                        "The sides beside a continuous side must leave it within the face's tangent plane.", featureID)
                }
            }
            let magnitude = support.tension * 0.5 * (start.length + end.length)
            var result = directions.map { $0 * magnitude }
            result[0] = start
            result[result.count - 1] = end
            return result
        }
        /// The second-derivative rows across a side: beside a curvature-continuous support the
        /// face's normal curvature along the first rows (zero beside a plane, whose neighbouring
        /// sides must then not bend out of it at the corners), otherwise the linear blend.
        func secondRows(_ side: BSplineCurve3D, support: ExactEdgeContinuitySupport?, first: [Vector3D], start: Vector3D, end: Vector3D) throws -> [Vector3D] {
            guard let support, support.order == .curvature else { return linear(side, start, end) }
            if support.isExact {
                let scale = max(start.length, end.length, 1)
                let (n0, n1) = (try support.normal(at: try point(side, 0), tolerance: tolerance),
                                try support.normal(at: try point(side, 1), tolerance: tolerance))
                guard abs(start.dot(n0)) <= tolerance.angle * scale, abs(end.dot(n1)) <= tolerance.angle * scale else {
                    throw failure(.invalidInput,
                        "The sides beside a curvature-continuous side must not bend out of the face's plane there.", featureID)
                }
            }
            var result = try support.curvatureRows(along: side, rows: first, tolerance: tolerance)
            result[0] = start
            result[result.count - 1] = end
            return result
        }
        // rows[k][c]: the k-th derivative across the side at v = c (along u) and columns[k][c] at
        // u = c (along v); k = 0 is the side itself.
        let vectors = { (curve: BSplineCurve3D) in curve.controlPoints.map { $0 - Point3D.origin } }
        var rows: [[[Vector3D]]] = [[vectors(b0), vectors(b1)]]
        var columns: [[[Vector3D]]] = [[vectors(a0), vectors(a1)]]
        rows.append([
            try firstRows(b0, support: supports[0], start: jet[0][0][0][1], end: jet[1][0][0][1], entering: false),
            try firstRows(b1, support: supports[1], start: jet[0][1][0][1], end: jet[1][1][0][1], entering: true),
        ])
        columns.append([
            try firstRows(a0, support: supports[2], start: jet[0][0][1][0], end: jet[0][1][1][0], entering: false),
            try firstRows(a1, support: supports[3], start: jet[1][0][1][0], end: jet[1][1][1][0], entering: true),
        ])
        if order == 2 {
            rows.append([
                try secondRows(b0, support: supports[0], first: rows[1][0], start: jet[0][0][0][2], end: jet[1][0][0][2]),
                try secondRows(b1, support: supports[1], first: rows[1][1], start: jet[0][1][0][2], end: jet[1][1][0][2]),
            ])
            columns.append([
                try secondRows(a0, support: supports[2], first: columns[1][0], start: jet[0][0][2][0], end: jet[0][1][2][0]),
                try secondRows(a1, support: supports[3], first: columns[1][1], start: jet[1][0][2][0], end: jet[1][1][2][0]),
            ])
        }
        // Each mixed derivative at a corner is read from the rows along u and the columns along v
        // and agreed as their mean; in the corner's tangent plane when a support borders it (where
        // planar faces must be one plane, so the agreed jets keep both exactly).
        let rowSupports = [supports[0], supports[1]], columnSupports = [supports[2], supports[3]]
        for cu in 0...1 {
            for cv in 0...1 {
                let pair = (rowSupports[cv], columnSupports[cu])
                let corner = Point3D.origin + jet[cu][cv][0][0]
                if let p = pair.0, let q = pair.1, p.isExact, q.isExact {
                    let (m, n) = (try p.normal(at: corner, tolerance: tolerance), try q.normal(at: corner, tolerance: tolerance))
                    guard m.cross(n).length <= tolerance.angle else {
                        throw failure(.invalidInput, "Planar faces meeting at a continuous corner must be one plane.", featureID)
                    }
                }
                let normal = try jet[cu][cv][1][0].cross(jet[cu][cv][0][1]).normalized(tolerance: tolerance.distance)
                let exactPlane = [pair.0, pair.1].contains { $0?.isExact == true }
                for j in 1...order {
                    for k in 1...order {
                        // ∂ʲ/∂uʲ of the k-th row across v = cv, and ∂ᵏ/∂vᵏ of the j-th column.
                        let fromRow = endDerivatives(rows[k][cv], alongU[cv], atEnd: cu == 1)[j - 1]
                        let fromColumn = endDerivatives(columns[j][cu], alongV[cu], atEnd: cv == 1)[k - 1]
                        let mean = (fromRow + fromColumn) * 0.5
                        // The twist always keeps the tangent plane; higher jets only beside a plane,
                        // whose rows lie in it (a curved face's rows bend out of it as the face does).
                        jet[cu][cv][j][k] = (j == 1 && k == 1) || exactPlane ? mean - normal * mean.dot(normal) : mean
                    }
                }
            }
        }
        for k in 1...order {
            for c in 0...1 {
                rows[k][c] = try impose(rows[k][c], alongU[c],
                                        start: (1...order).map { jet[0][c][$0][k] }, end: (1...order).map { jet[1][c][$0][k] })
                columns[k][c] = try impose(columns[k][c], alongV[c],
                                           start: (1...order).map { jet[c][0][k][$0] }, end: (1...order).map { jet[c][1][k][$0] })
            }
        }
        // The Hermite functions as Bézier coefficients on [0, 1], each with the corner it is at and
        // the derivative order it carries, and their coefficients in each basis.
        let hermite: [(bezier: [Double], corner: Int, order: Int)] = order == 1
            ? [([1, 1, 0, 0], 0, 0), ([0, 0, 1, 1], 1, 0), ([0, 1.0 / 3, 0, 0], 0, 1), ([0, 0, -1.0 / 3, 0], 1, 1)]
            : [([1, 1, 1, 0, 0, 0], 0, 0), ([0, 0, 0, 1, 1, 1], 1, 0), ([0, 0.2, 0.4, 0, 0, 0], 0, 1),
               ([0, 0, 0, -0.4, -0.2, 0], 1, 1), ([0, 0, 0.05, 0, 0, 0], 0, 2), ([0, 0, 0, 0.05, 0, 0], 1, 2)]
        func coefficients(_ curve: BSplineCurve3D) -> [[Double]] {
            hermite.map { function in
                let elevated = elevate(function.bezier, to: curve.degree)
                return (0..<curve.controlPointCount).map { j in blossom(elevated, Array(curve.knots[(j + 1)...(j + curve.degree)])) }
            }
        }
        if [b0, b1, a0, a1].contains(where: { $0.weights.contains { $0 != 1 } }) {
            let surface = try rationalAllSides(hermite: hermite, rows: rows, columns: columns, jet: jet, b0: b0, b1: b1, a0: a0, a1: a1)
            try surface.validate(tolerance: tolerance)
            return (try ExactLoftSideSurfaceBuilder().validated(surface, tolerance: tolerance), [b0, b1, a0, a1])
        }
        let cu = coefficients(b0), cv = coefficients(a0)
        let net = try (0..<a0.controlPointCount).map { j in
            try (0..<b0.controlPointCount).map { i -> Point3D in
                var value = Vector3D.zero
                for (k, function) in hermite.enumerated() {
                    value = value + rows[function.order][function.corner][i] * cv[k][j]
                        + columns[function.order][function.corner][j] * cu[k][i]
                }
                for (a, f) in hermite.enumerated() {
                    for (b, g) in hermite.enumerated() {
                        value = value - jet[f.corner][g.corner][f.order][g.order] * (cu[a][i] * cv[b][j])
                    }
                }
                try value.validate()
                return .origin + value
            }
        }
        let surface = BSplineSurface3D(uDegree: b0.degree, vDegree: a0.degree, uKnots: b0.knots, vKnots: a0.knots, controlPoints: net)
        try surface.validate(tolerance: tolerance)
        return (try ExactLoftSideSurfaceBuilder().validated(surface, tolerance: tolerance), [b0, b1, a0, a1])
    }

    /// The first and second derivatives of the clamped spline with `coefficients` in `curve`'s
    /// basis at its start or end: the derivative splines' end coefficients.
    private func endDerivatives(_ coefficients: [Vector3D], _ curve: BSplineCurve3D, atEnd: Bool) -> [Vector3D] {
        let (values, knots) = atEnd ? reversed(coefficients, curve) : (coefficients, curve.knots)
        let p = Double(curve.degree)
        let q0 = (values[1] - values[0]) * (p / (knots[curve.degree + 1] - knots[1]))
        let q1 = (values[2] - values[1]) * (p / (knots[curve.degree + 2] - knots[2]))
        let second = (q1 - q0) * ((p - 1) / (knots[curve.degree + 1] - knots[2]))
        return atEnd ? [q0 * -1, second] : [q0, second]
    }

    /// `coefficients` with their first (and second) derivatives at the start and end replaced by
    /// the given ones: the two (three) end coefficients at each end, which need a basis of at least
    /// twice as many.
    private func impose(_ coefficients: [Vector3D], _ curve: BSplineCurve3D, start: [Vector3D], end: [Vector3D]) throws -> [Vector3D] {
        guard coefficients.count >= 2 * (start.count + 1) else {
            throw KernelError(phase: .evaluation, code: .invalidInput, tolerance: tolerance,
                              message: "A side's basis is too small for its corner derivatives.")
        }
        func imposingStart(_ values: [Vector3D], _ knots: [Double], _ derivatives: [Vector3D]) -> [Vector3D] {
            var values = values
            let p = Double(curve.degree)
            let q0 = derivatives[0]
            values[1] = values[0] + q0 * ((knots[curve.degree + 1] - knots[1]) / p)
            if derivatives.count > 1 {
                let q1 = q0 + derivatives[1] * ((knots[curve.degree + 1] - knots[2]) / (p - 1))
                values[2] = values[1] + q1 * ((knots[curve.degree + 2] - knots[2]) / p)
            }
            return values
        }
        let started = imposingStart(coefficients, curve.knots, start)
        let (back, knots) = reversed(started, curve)
        let ended = imposingStart(back, knots, end.enumerated().map { $0.offset == 0 ? $0.element * -1 : $0.element })
        return Array(ended.reversed())
    }

    /// The coefficients and knots of `curve`'s basis run backwards over the same domain.
    private func reversed(_ coefficients: [Vector3D], _ curve: BSplineCurve3D) -> ([Vector3D], [Double]) {
        let (first, last) = (curve.knots[0], curve.knots[curve.knots.count - 1])
        return (Array(coefficients.reversed()), curve.knots.reversed().map { first + last - $0 })
    }

    /// The four-sided Boolean sum with rational sides: the Hermite blends of the rows across v and
    /// of the columns across u less the tensor of the corner jets, the rows and columns of order
    /// zero the sides themselves, over the common denominator `w_b·w_t (u) · w_l·w_r (v)`.
    private func rationalAllSides(
        hermite: [(bezier: [Double], corner: Int, order: Int)], rows: [[[Vector3D]]], columns: [[[Vector3D]]],
        jet: [[[[Vector3D]]]], b0: BSplineCurve3D, b1: BSplineCurve3D, a0: BSplineCurve3D, a1: BSplineCurve3D
    ) throws -> BSplineSurface3D {
        let sum = ExactRationalBooleanSum(tolerance: tolerance)
        func breakpoints(_ knots: [Double]) -> [Double] {
            var distinct: [Double] = []
            for knot in knots where distinct.last.map({ knot > $0 }) ?? true { distinct.append(knot) }
            return distinct
        }
        let (ub, vb) = (breakpoints(b0.knots), breakpoints(a0.knots))
        func scalar(_ value: Double) -> Vector3D { Vector3D(x: value, y: 0, z: 0) }
        func split(_ curve: BSplineCurve3D, on points: [Double]) throws -> (ExactRationalBooleanSum.Pieces, ExactRationalBooleanSum.Pieces) {
            let numerator = try sum.pieces(coefficients: zip(curve.controlPoints, curve.weights).map { ($0 - .origin) * $1 },
                                           knots: curve.knots, degree: curve.degree)
            let weight = curve.weights.allSatisfy { $0 == 1 }
                ? sum.pieces(bezier: [scalar(1)], breakpoints: points)
                : try sum.pieces(coefficients: curve.weights.map(scalar), knots: curve.knots, degree: curve.degree)
            return (numerator, weight)
        }
        let (nb, wb) = try split(b0, on: ub), (nt, wt) = try split(b1, on: ub)
        let (nl, wl) = try split(a0, on: vb), (nr, wr) = try split(a1, on: vb)
        let wu = try sum.product(wb, scalar: wt), wv = try sum.product(wl, scalar: wr)
        var products: [ExactRationalBooleanSum.Term] = []
        for function in hermite {
            let hv = try sum.product(sum.pieces(bezier: function.bezier.map(scalar), breakpoints: vb), scalar: wv)
            let hu = try sum.product(sum.pieces(bezier: function.bezier.map(scalar), breakpoints: ub), scalar: wu)
            let row = function.order == 0
                ? try sum.product(function.corner == 0 ? nb : nt, scalar: function.corner == 0 ? wt : wb)
                : try sum.product(try sum.pieces(coefficients: rows[function.order][function.corner], knots: b0.knots, degree: b0.degree), scalar: wu)
            let column = function.order == 0
                ? try sum.product(function.corner == 0 ? nl : nr, scalar: function.corner == 0 ? wr : wl)
                : try sum.product(try sum.pieces(coefficients: columns[function.order][function.corner], knots: a0.knots, degree: a0.degree), scalar: wv)
            products.append(.init(u: row, v: hv, vectorAlongU: true))
            products.append(.init(u: hu, v: column, vectorAlongU: false))
        }
        for f in hermite {
            let hu = try sum.product(sum.pieces(bezier: f.bezier.map(scalar), breakpoints: ub), scalar: wu)
            for g in hermite {
                let value = jet[f.corner][g.corner][f.order][g.order] * -1
                let hv = try sum.product(sum.pieces(bezier: g.bezier.map { value * $0 }, breakpoints: vb), scalar: wv)
                products.append(.init(u: hu, v: hv, vectorAlongU: false))
            }
        }
        return try sum.surface(terms: products, denominatorU: wu, denominatorV: wv)
    }

    /// The Boolean sum with rational sides: `(1 − u)·left + u·right + Σ Hₖ(v)·(rowₖ(u) − the linear
    /// blend of its ends)`, its rows the bottom and top sides themselves and then the derivative
    /// rows, over the common denominator `w_b·w_t (u) · w_l·w_r (v)`.
    private func rationalSum(
        terms: [(bezier: [Double], rows: [Vector3D], left: Vector3D, right: Vector3D)],
        b0: BSplineCurve3D, b1: BSplineCurve3D, a0: BSplineCurve3D, a1: BSplineCurve3D
    ) throws -> BSplineSurface3D {
        let sum = ExactRationalBooleanSum(tolerance: tolerance)
        func breakpoints(_ knots: [Double]) -> [Double] {
            var distinct: [Double] = []
            for knot in knots where distinct.last.map({ knot > $0 }) ?? true { distinct.append(knot) }
            return distinct
        }
        let (ub, vb) = (breakpoints(b0.knots), breakpoints(a0.knots))
        func scalar(_ value: Double) -> Vector3D { Vector3D(x: value, y: 0, z: 0) }
        /// A side's numerator (weighted control points) and its weight function.
        func split(_ curve: BSplineCurve3D, on points: [Double]) throws -> (ExactRationalBooleanSum.Pieces, ExactRationalBooleanSum.Pieces) {
            let numerator = try sum.pieces(coefficients: zip(curve.controlPoints, curve.weights).map { ($0 - .origin) * $1 },
                                           knots: curve.knots, degree: curve.degree)
            let weight = curve.weights.allSatisfy { $0 == 1 }
                ? sum.pieces(bezier: [scalar(1)], breakpoints: points)
                : try sum.pieces(coefficients: curve.weights.map(scalar), knots: curve.knots, degree: curve.degree)
            return (numerator, weight)
        }
        let (nb, wb) = try split(b0, on: ub), (nt, wt) = try split(b1, on: ub)
        let (nl, wl) = try split(a0, on: vb), (nr, wr) = try split(a1, on: vb)
        let wu = try sum.product(wb, scalar: wt), wv = try sum.product(wl, scalar: wr)
        let oneMinusU = sum.pieces(bezier: [scalar(1), scalar(0)], breakpoints: ub)
        let u = sum.pieces(bezier: [scalar(0), scalar(1)], breakpoints: ub)
        var products: [ExactRationalBooleanSum.Term] = [
            .init(u: try sum.product(oneMinusU, scalar: wu), v: try sum.product(nl, scalar: wr), vectorAlongU: false),
            .init(u: try sum.product(u, scalar: wu), v: try sum.product(nr, scalar: wl), vectorAlongU: false),
        ]
        for (index, term) in terms.enumerated() {
            let blend = try sum.product(sum.pieces(bezier: [term.left, term.right], breakpoints: ub), scalar: wu)
            let row: ExactRationalBooleanSum.Pieces
            switch index {
            case 0: row = try sum.product(nb, scalar: wt)
            case 1: row = try sum.product(nt, scalar: wb)
            default: row = try sum.product(try sum.pieces(coefficients: term.rows, knots: b0.knots, degree: b0.degree), scalar: wu)
            }
            products.append(.init(u: try sum.sum(row, sum.scaled(blend, by: -1)),
                                  v: try sum.product(sum.pieces(bezier: term.bezier.map(scalar), breakpoints: vb), scalar: wv),
                                  vectorAlongU: true))
        }
        return try sum.surface(terms: products, denominatorU: wu, denominatorV: wv)
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
