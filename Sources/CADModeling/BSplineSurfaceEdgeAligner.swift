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
package struct BSplineSurfaceEdgeAligner: Sendable {
    package typealias Side = BSplineSurfaceBoundaryExtender.Side

    package init() {}

    /// `target` with its `targetSide` edge aligned to `reference`'s `referenceSide` edge; `continuity`
    /// is 0 (G0), 1 (G1) or 2 (G2).
    package func aligned(
        _ target: BSplineSurface3D, side targetSide: Side,
        to reference: BSplineSurface3D, side referenceSide: Side,
        continuity: Int, tension: Double, blendRows: Int, inputShapeInfluence: Double = 1,
        partialStart: Double = 0, partialEnd: Double = 0, layout: MappedBSplineSurfaceFitter.Layout? = nil,
        tolerance: ModelingTolerance
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
