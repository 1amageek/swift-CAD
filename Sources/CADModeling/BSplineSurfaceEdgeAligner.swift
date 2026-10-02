import Foundation
import CADCore
import CADGeometry

/// Align Surface on B-spline surfaces: a target surface's boundary edge made to follow a reference
/// surface's boundary edge with positional, tangent-plane or curvature continuity.
///
/// Both surfaces are brought to one basis along the edge exactly (their edge parameters mapped to
/// `[0, 1]`, the lower degree raised and each one's knots inserted into the other), so the
/// target's control rows at the edge can be set from the reference's end rows: the first row to
/// the reference's boundary curve (G0), the second so the cross-edge derivative is the
/// reference's times the tension-scaled speed ratio (G1), the third so the second derivative is
/// its square times the reference's (G2). The displacement of the last row set fades over
/// `blendRows` further rows, by their Greville abscissae, toward the first row left alone; a
/// blended row keeps `inputShapeInfluence` of its own shape, the rest running straight between
/// those two rows. The whole change fades in over the first `partialStart` of the edge and out
/// over its last `partialEnd` (smoothstep in each column's Greville abscissa along the edge), and
/// a `layout` refits the target to its degrees and spans on its own parameters first. Both
/// surfaces must be non-rational, whose control points combine affinely.
///
/// The cross-edge flow (G1 and G2) is the reference's own cross derivative scaled (`next`: the
/// reference's next inner row's flow) or, for the other flows, `D = a·R_v + b·R_u` with `a`, `b`
/// quadratic polynomials along the edge fitted to the flow's direction — perpendicular to the edge
/// (`normal`), the target's own cross direction (`natural`), or the blend of the target's side
/// edges' directions (`adjacent`), each in the reference's tangent plane — so the target near the
/// edge is the reference reparameterised by `(v + a·w, b·w)` to second order: its second derivative
/// is `b²·R_uu + 2ab·R_uv + a²·R_vv`, curvature continuous exactly. Those products lie in the
/// target's basis along the edge raised by 2 (4 at G2) with its interior knots one (two) more times
/// repeated, where both surfaces are carried exactly and the rows are interpolated at the Greville
/// abscissae.
package struct BSplineSurfaceEdgeAligner: Sendable {
    package typealias Side = BSplineSurfaceBoundaryExtender.Side

    /// The cross-edge flow along a G1 or G2 edge.
    package enum Flow: Sendable {
        case natural
        case normal
        case next
        case adjacent
    }

    package init() {}

    /// `target` with its `targetSide` edge aligned to `reference`'s `referenceSide` edge; `continuity`
    /// is 0 (G0), 1 (G1) or 2 (G2).
    package func aligned(
        _ target: BSplineSurface3D, side targetSide: Side,
        to reference: BSplineSurface3D, side referenceSide: Side,
        continuity: Int, tension: Double, blendRows: Int, inputShapeInfluence: Double = 1,
        partialStart: Double = 0, partialEnd: Double = 0, layout: MappedBSplineSurfaceFitter.Layout? = nil,
        flow: Flow = .next, tolerance: ModelingTolerance
    ) throws -> BSplineSurface3D {
        guard (0...2).contains(continuity), tension.isFinite, tension > 0, blendRows >= 0, (0...1).contains(inputShapeInfluence),
              (0...1).contains(partialStart), (0...1).contains(partialEnd), partialStart + partialEnd <= 1 else {
            throw failure(.invalidInput, "Align Surface takes G0, G1 or G2, a positive tension, blended rows none or more, an influence and partial fractions within 0 to 1.", tolerance)
        }
        for surface in [target, reference] where surface.weights.joined().contains(where: { abs($0 - 1) > 1e-12 }) {
            throw failure(.unsupportedCapability, "Align Surface aligns non-rational B-spline surfaces.", tolerance)
        }
        var target = target
        if let layout {
            let own = target
            guard let u0 = own.uKnots.first, let u1 = own.uKnots.last, let v0 = own.vKnots.first, let v1 = own.vKnots.last else {
                throw failure(.invalidInput, "A target surface has no parameter domain.", tolerance)
            }
            target = try MappedBSplineSurfaceFitter.fit(
                layout: layout, u: ScalarInterval(lower: u0, upper: u1), v: ScalarInterval(lower: v0, upper: v1), tolerance: tolerance
            ) { u, v in try Surface3D.bSpline(own).differentialGeometry(u: u, v: v, tolerance: tolerance).position }.surface
        }
        // The target's edge at its lower U boundary, its interior after it; the reference's at its
        // upper U boundary, its interior before it.
        var working = oriented(target, side: targetSide, toLower: true)
        var guide = oriented(reference, side: referenceSide, toLower: false)
        let evaluate = { (surface: BSplineSurface3D, u: Double, v: Double) throws -> Point3D in
            try Surface3D.bSpline(surface).differentialGeometry(u: u, v: v, tolerance: tolerance).position
        }
        // The reference runs along the edge the way the target does.
        let (tu, tv0, tv1) = (working.uKnots.first ?? 0, working.vKnots.first ?? 0, working.vKnots.last ?? 0)
        let (gu, gv0, gv1) = (guide.uKnots.last ?? 0, guide.vKnots.first ?? 0, guide.vKnots.last ?? 0)
        let (ts, te) = (try evaluate(working, tu, tv0), try evaluate(working, tu, tv1))
        let (gs, ge) = (try evaluate(guide, gu, gv0), try evaluate(guide, gu, gv1))
        if (ts - gs).length + (te - ge).length > (ts - ge).length + (te - gs).length {
            guide = transposed(reversedU(transposed(guide)))
        }
        working = unitV(working)
        guide = unitV(guide)
        while working.vDegree < guide.vDegree { working = try working.elevatingDegree(direction: .v, tolerance: tolerance) }
        while guide.vDegree < working.vDegree { guide = try guide.elevatingDegree(direction: .v, tolerance: tolerance) }
        for value in Set(working.vKnots + guide.vKnots).sorted() {
            let needed = max(multiplicity(of: value, in: working.vKnots, tolerance), multiplicity(of: value, in: guide.vKnots, tolerance))
            while multiplicity(of: value, in: working.vKnots, tolerance) < needed {
                working = try working.insertingKnot(direction: .v, value: value, tolerance: tolerance)
            }
            while multiplicity(of: value, in: guide.vKnots, tolerance) < needed {
                guide = try guide.insertingKnot(direction: .v, value: value, tolerance: tolerance)
            }
        }
        // Enough rows along U: the rows set, the rows blended, and the far row untouched.
        let setRows = continuity + 1
        while working.uDegree < max(continuity, 1) { working = try working.elevatingDegree(direction: .u, tolerance: tolerance) }
        while (working.controlPoints.first?.count ?? 0) < setRows + blendRows + 1 {
            let knots = working.uKnots
            guard let first = knots.first, let next = knots.first(where: { $0 > first + tolerance.distance }) else {
                throw failure(.invalidInput, "A target surface has no U span to refine.", tolerance)
            }
            working = try working.insertingKnot(direction: .u, value: (first + next) / 2, tolerance: tolerance)
        }
        guard working.controlPoints.count == guide.controlPoints.count else {
            throw failure(.topologyFailure, "The aligned edges did not reach one basis.", tolerance)
        }
        if continuity >= 1, flow != .next {
            return try flowAligned(working, guide: guide, targetSide: targetSide, continuity: continuity, tension: tension,
                                   blendRows: blendRows, inputShapeInfluence: inputShapeInfluence, partialStart: partialStart,
                                   partialEnd: partialEnd, flow: flow, tolerance: tolerance)
        }
        // The reference's boundary row and its derivatives across the edge, column by column.
        let p = guide.uDegree
        let n = (guide.controlPoints.first?.count ?? 0) - 1
        let U = guide.uKnots
        let q = working.uDegree
        let V = working.uKnots
        let columns = working.controlPoints.count
        var derivatives: [(point: Point3D, first: Vector3D, second: Vector3D)] = []
        for j in 0..<columns {
            let row = guide.controlPoints[j]
            let first = (row[n] - row[n - 1]) * (Double(p) / (U[n + p] - U[n]))
            var second = Vector3D.zero
            if p >= 2, n >= 2 {
                let before = (row[n - 1] - row[n - 2]) * (Double(p) / (U[n + p - 1] - U[n - 1]))
                second = (first - before) * (Double(p - 1) / (U[n + p - 1] - U[n]))
            }
            derivatives.append((row[n], first, second))
        }
        // The speed across the edge scales by the tension times the target's own speed ratio.
        let middle = columns / 2
        let ownSpeed = ((working.controlPoints[middle][1] - working.controlPoints[middle][0]) * (Double(q) / (V[q + 1] - V[1]))).length
        let guideSpeed = derivatives[middle].first.length
        guard guideSpeed > tolerance.distance, ownSpeed > tolerance.distance else {
            throw failure(.topologyFailure, "An aligned edge has no speed across it.", tolerance)
        }
        let scale = tension * ownSpeed / guideSpeed
        var aligned = working.controlPoints
        // Greville abscissae across the edge (rows) and along it (columns, on [0, 1]).
        let rowAbscissae = greville(V, degree: q, count: working.controlPoints[0].count)
        let columnAbscissae = greville(working.vKnots, degree: working.vDegree, count: columns)
        let lastSet = setRows - 1
        let firstLeft = setRows + blendRows
        for j in 0..<columns {
            let (point, first, second) = derivatives[j]
            let old = working.controlPoints[j]
            aligned[j][0] = point
            if continuity >= 1 {
                aligned[j][1] = point + first * (scale * (V[q + 1] - V[1]) / Double(q))
            }
            if continuity >= 2 {
                let q0 = first * scale
                let q1 = q0 + second * (scale * scale * (V[q + 1] - V[2]) / Double(q - 1))
                aligned[j][2] = aligned[j][1] + q1 * ((V[q + 2] - V[2]) / Double(q))
            }
            // The last row set carries the rows after it part of its way, each keeping the input
            // shape's influence and running straight toward the first row left alone otherwise.
            let displacement = aligned[j][lastSet] - old[lastSet]
            let span = rowAbscissae[firstLeft] - rowAbscissae[lastSet]
            for k in setRows..<firstLeft {
                let t = (rowAbscissae[k] - rowAbscissae[lastSet]) / span
                let carried = old[k] + displacement * (1 - t)
                let straight = aligned[j][lastSet] + (old[firstLeft] - aligned[j][lastSet]) * t
                aligned[j][k] = carried + (straight - carried) * (1 - inputShapeInfluence)
            }
            // Partial alignment: the change fades in and out along the edge.
            let weight = partialWeight(at: columnAbscissae[j], start: partialStart, end: partialEnd)
            for k in 0..<firstLeft {
                aligned[j][k] = old[k] + (aligned[j][k] - old[k]) * weight
            }
        }
        working.controlPoints = aligned
        // Back to the target's own orientation.
        return oriented(working, side: targetSide, toLower: true, undoing: true)
    }

    /// The alignment with a flow other than Next: both surfaces raised along the edge into the
    /// space of the products, the rows set from `D = a·R_v + b·R_u` and its second derivative.
    private func flowAligned(
        _ start: BSplineSurface3D, guide startGuide: BSplineSurface3D, targetSide: Side, continuity: Int, tension: Double,
        blendRows: Int, inputShapeInfluence: Double, partialStart: Double, partialEnd: Double, flow: Flow,
        tolerance: ModelingTolerance
    ) throws -> BSplineSurface3D {
        var working = start, guide = startGuide
        // The target's own cross derivatives (Natural, Adjacent), read before it is changed.
        let own = Surface3D.bSpline(working)
        let (tu, gu) = (working.uKnots.first ?? 0, guide.uKnots.last ?? 0)
        func ownCross(_ v: Double) throws -> Vector3D {
            try own.differentialGeometry(u: tu, v: v, tolerance: tolerance).tangentU
        }
        // The products' space: degree raised by 2 per order, interior knots repeated once more per order.
        let interior = Array(Set(working.vKnots.filter { $0 > 0 && $0 < 1 })).sorted()
        for _ in 0..<(2 * continuity) {
            working = try working.elevatingDegree(direction: .v, tolerance: tolerance)
            guide = try guide.elevatingDegree(direction: .v, tolerance: tolerance)
        }
        for value in interior {
            for _ in 0..<continuity {
                working = try working.insertingKnot(direction: .v, value: value, tolerance: tolerance)
                guide = try guide.insertingKnot(direction: .v, value: value, tolerance: tolerance)
            }
        }
        guard working.controlPoints.count == guide.controlPoints.count else {
            throw failure(.topologyFailure, "The aligned edges did not reach one basis.", tolerance)
        }
        let reference = Surface3D.bSpline(guide)
        // The coefficients a(v), b(v): quadratics fitted to the flow at nine stations.
        let middleSpeed = try ownCross(0.5).length
        let guideMiddle = try reference.differentialGeometry(u: gu, v: 0.5, tolerance: tolerance)
        guard middleSpeed > tolerance.distance, guideMiddle.tangentU.length > tolerance.distance else {
            throw failure(.topologyFailure, "An aligned edge has no speed across it.", tolerance)
        }
        let scale = tension * middleSpeed / guideMiddle.tangentU.length
        let (corner0, corner1) = (try ownCross(0), try ownCross(1))
        var samples: [(v: Double, a: Double, b: Double)] = []
        for k in 0...8 {
            let v = Double(k) / 8
            let jet = try reference.differentialGeometry(u: gu, v: v, tolerance: tolerance)
            let (ru, rv) = (jet.tangentU, jet.tangentV)
            let (a, b): (Double, Double)
            switch flow {
            case .next:
                (a, b) = (0, scale)
            case .normal:
                (a, b) = (-scale * ru.dot(rv) / rv.dot(rv), scale)
            case .natural, .adjacent:
                let wanted = flow == .natural ? try ownCross(v) : corner0 * (1 - v) + corner1 * v
                // In the tangent plane, as a·R_v + b·R_u (least squares), at the target's speed.
                let unit = try wanted.normalized(tolerance: tolerance.distance) * (tension * middleSpeed)
                let (e, f, g) = (rv.dot(rv), rv.dot(ru), ru.dot(ru))
                let (p, q) = (unit.dot(rv), unit.dot(ru))
                let determinant = e * g - f * f
                guard determinant > 0 else { throw failure(.topologyFailure, "A reference edge is degenerate.", tolerance) }
                (a, b) = ((g * p - f * q) / determinant, (e * q - f * p) / determinant)
            }
            guard b > 0 else {
                throw failure(.invalidInput, "The flow turns back across the aligned edge.", tolerance)
            }
            samples.append((v, a, b))
        }
        func quadratic(_ values: [Double]) throws -> (Double) -> Double {
            // Least squares in 1, v, v².
            var normal = [[Double]](repeating: [0, 0, 0], count: 3), right = [0.0, 0, 0]
            for (sample, value) in zip(samples, values) {
                let basis = [1, sample.v, sample.v * sample.v]
                for i in 0..<3 {
                    right[i] += basis[i] * value
                    for j in 0..<3 { normal[i][j] += basis[i] * basis[j] }
                }
            }
            let qr = try SurfaceFittingQR(coefficients: normal.flatMap { $0 }, rows: 3, columns: 3, relativeRankTolerance: 1e-14,
                                          maximumElements: 9)
            let c = try qr.solveFullRankLeastSquares(right)
            return { v in c[0] + c[1] * v + c[2] * v * v }
        }
        let a = try quadratic(samples.map(\.a)), b = try quadratic(samples.map(\.b))
        // The derivative curves across the edge, interpolated at the Greville abscissae of the
        // raised basis, where they lie exactly.
        let q = working.uDegree
        let V = working.uKnots
        let columns = working.controlPoints.count
        let vKnots = working.vKnots, vDegree = working.vDegree
        let abscissae = greville(vKnots, degree: vDegree, count: columns)
        var matrix: [Double] = []
        for g in abscissae {
            matrix += BSplineBasis.values(parameter: BSplineBasis.clampedParameter(g, knots: vKnots, degree: vDegree),
                                          degree: vDegree, knots: vKnots, count: columns)
        }
        let collocation = try SurfaceFittingQR(coefficients: matrix, rows: columns, columns: columns, relativeRankTolerance: 1e-13,
                                               maximumElements: max(1 << 16, columns * columns))
        func interpolated(_ values: [Vector3D]) throws -> [Vector3D] {
            let x = try collocation.solveFullRankLeastSquares(values.map(\.x))
            let y = try collocation.solveFullRankLeastSquares(values.map(\.y))
            let z = try collocation.solveFullRankLeastSquares(values.map(\.z))
            return (0..<columns).map { Vector3D(x: x[$0], y: y[$0], z: z[$0]) }
        }
        var first: [Vector3D] = [], second: [Vector3D] = []
        for g in abscissae {
            let jet = try reference.differentialGeometry(u: gu, v: g, tolerance: tolerance)
            let (av, bv) = (a(g), b(g))
            first.append(jet.tangentV * av + jet.tangentU * bv)
            second.append(jet.secondDerivativeUU * (bv * bv) + jet.secondDerivativeUV * (2 * av * bv) + jet.secondDerivativeVV * (av * av))
        }
        let firstRows = try interpolated(first)
        let secondRows = continuity >= 2 ? try interpolated(second) : []
        // Enough rows across: the rows set, blended, and the far row.
        let setRows = continuity + 1
        var aligned = working.controlPoints
        let rowAbscissae = greville(V, degree: q, count: working.controlPoints[0].count)
        let columnAbscissae = greville(vKnots, degree: vDegree, count: columns)
        let lastSet = setRows - 1
        let firstLeft = setRows + blendRows
        let n = (guide.controlPoints.first?.count ?? 0) - 1
        for j in 0..<columns {
            let old = working.controlPoints[j]
            let point = guide.controlPoints[j][n]
            aligned[j][0] = point
            aligned[j][1] = point + firstRows[j] * ((V[q + 1] - V[1]) / Double(q))
            if continuity >= 2 {
                let q1 = firstRows[j] + secondRows[j] * ((V[q + 1] - V[2]) / Double(q - 1))
                aligned[j][2] = aligned[j][1] + q1 * ((V[q + 2] - V[2]) / Double(q))
            }
            let displacement = aligned[j][lastSet] - old[lastSet]
            let span = rowAbscissae[firstLeft] - rowAbscissae[lastSet]
            for k in setRows..<firstLeft {
                let t = (rowAbscissae[k] - rowAbscissae[lastSet]) / span
                let carried = old[k] + displacement * (1 - t)
                let straight = aligned[j][lastSet] + (old[firstLeft] - aligned[j][lastSet]) * t
                aligned[j][k] = carried + (straight - carried) * (1 - inputShapeInfluence)
            }
            let weight = partialWeight(at: columnAbscissae[j], start: partialStart, end: partialEnd)
            for k in 0..<firstLeft {
                aligned[j][k] = old[k] + (aligned[j][k] - old[k]) * weight
            }
        }
        working.controlPoints = aligned
        return oriented(working, side: targetSide, toLower: true, undoing: true)
    }

    /// The surface turned so `side` becomes its lower U boundary (`toLower`) or its upper one;
    /// `undoing` turns it back.
    private func oriented(_ surface: BSplineSurface3D, side: Side, toLower: Bool, undoing: Bool = false) -> BSplineSurface3D {
        let transposes = side == .vLower || side == .vUpper
        let atLower = side == .uLower || side == .vLower
        let reverses = atLower != toLower
        if undoing {
            var result = reverses ? reversedU(surface) : surface
            if transposes { result = transposed(result) }
            return result
        }
        var result = transposes ? transposed(surface) : surface
        if reverses { result = reversedU(result) }
        return result
    }

    private func greville(_ knots: [Double], degree: Int, count: Int) -> [Double] {
        (0..<count).map { index in knots[(index + 1)...(index + degree)].reduce(0, +) / Double(degree) }
    }

    /// How much of the alignment a column at `s` along the edge takes: none at either end within a
    /// partial fraction, rising smoothly to all of it where the fraction ends.
    private func partialWeight(at s: Double, start: Double, end: Double) -> Double {
        func smooth(_ x: Double) -> Double { let t = min(max(x, 0), 1); return t * t * (3 - 2 * t) }
        var weight = 1.0
        if start > 0, s < start { weight = min(weight, smooth(s / start)) }
        if end > 0, s > 1 - end { weight = min(weight, smooth((1 - s) / end)) }
        return weight
    }

    /// The surface with its V parameter mapped onto `[0, 1]`.
    private func unitV(_ surface: BSplineSurface3D) -> BSplineSurface3D {
        guard let first = surface.vKnots.first, let last = surface.vKnots.last, last > first else { return surface }
        var result = surface
        result.vKnots = surface.vKnots.map { ($0 - first) / (last - first) }
        return result
    }

    private func multiplicity(of value: Double, in knots: [Double], _ tolerance: ModelingTolerance) -> Int {
        knots.filter { abs($0 - value) <= 1e-12 }.count
    }

    private func reversedU(_ surface: BSplineSurface3D) -> BSplineSurface3D {
        let first = surface.uKnots.first ?? 0
        let last = surface.uKnots.last ?? 0
        return BSplineSurface3D(
            uDegree: surface.uDegree, vDegree: surface.vDegree,
            uKnots: surface.uKnots.reversed().map { first + last - $0 }, vKnots: surface.vKnots,
            controlPoints: surface.controlPoints.map { Array($0.reversed()) }, weights: surface.weights.map { Array($0.reversed()) }
        )
    }

    private func transposed(_ surface: BSplineSurface3D) -> BSplineSurface3D {
        let rows = surface.controlPoints.count
        let columns = surface.controlPoints.first?.count ?? 0
        return BSplineSurface3D(
            uDegree: surface.vDegree, vDegree: surface.uDegree, uKnots: surface.vKnots, vKnots: surface.uKnots,
            controlPoints: (0..<columns).map { u in (0..<rows).map { surface.controlPoints[$0][u] } },
            weights: (0..<columns).map { u in (0..<rows).map { surface.weights[$0][u] } }
        )
    }

    private func failure(_ code: KernelErrorCode, _ message: String, _ tolerance: ModelingTolerance) -> KernelError {
        KernelError(phase: .evaluation, code: code, tolerance: tolerance, message: message)
    }
}
