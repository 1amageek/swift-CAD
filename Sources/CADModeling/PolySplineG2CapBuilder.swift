import Foundation
import CADCore
import CADGeometry

/// The G2 cap of PolySplines around an inner extraordinary vertex: one Bézier patch of degree
/// eight per quad around it, curvature continuous across every edge.
///
/// Sector k's patch q_k(u, v) has the vertex at (0, 0); its v = 0 side runs along the edge it
/// shares with sector k − 1 (whose u = 0 side it is) and its u = 0 side along the edge it shares
/// with sector k + 1, so q_{k+1}(t, 0) = q_k(0, t). Its other two sides border regular bicubic
/// patches (the uniform B-spline), which it meets with parametric C2: its last three rows toward
/// u = 1 and v = 1 are those patches' second-order Taylor data carried across, raised to degree
/// eight. Across the inner edges the sectors meet G2 under the reparametrization
/// s = −v + e(u)·v², t = u + b(u)·v + d(u)·v² of sector k + 1 into sector k:
///
///   ∂v q_{k+1} = −∂s q_k + b ∂t q_k
///   ∂vv q_{k+1} = ∂ss q_k − 2b ∂st q_k + b² ∂tt q_k + 2d ∂t q_k + 2e ∂s q_k
///
/// with b = 2c(1 − u)³ (c = cos 2π/n, the tangents' enclosure at the vertex) and
/// d = e = −6c²/(1 + c)·(1 − u)³ (the second-order enclosure: with b′(0) = −6c the sectors'
/// tangential second derivatives close around the vertex only for these, which n = 3 needs and
/// every other valence admits), all vanishing to third order at u = 1 where the edge runs into the
/// regular grid. The conditions are polynomial identities of degree at most m + 4 along each edge,
/// imposed at m + 5 points, so they hold exactly; the vertex is held at its Catmull–Clark limit.
/// Of the patches satisfying them, the one of least thin-plate energy is taken. Degree eight
/// leaves every valence from three upward room for that choice; the conditions' residual is
/// checked, and a cap that cannot meet them is refused, never returned approximate.
package struct PolySplineG2CapBuilder {
    /// One sector's regular neighbours, as bicubic Bézier nets (rows along v, points along u) in
    /// frames continuing the sector's: `acrossU` beyond its u = 1 side (its u running on away from
    /// the side, its v as the sector's), `acrossV` beyond its v = 1 side.
    package struct Sector {
        package let acrossU: [[Point3D]]
        package let acrossV: [[Point3D]]

        package init(acrossU: [[Point3D]], acrossV: [[Point3D]]) {
            self.acrossU = acrossU
            self.acrossV = acrossV
        }
    }

    package static let degree = 8

    private let tolerance: ModelingTolerance

    package init(tolerance: ModelingTolerance) {
        self.tolerance = tolerance
    }

    /// The sectors' nets of degree eight (rows along v, points along u), in order.
    package func caps(apex: Point3D, sectors: [Sector]) throws -> [[[Point3D]]] {
        let n = sectors.count
        let m = Self.degree
        guard n >= 3, n != 4,
              sectors.allSatisfy({ $0.acrossU.count == 4 && $0.acrossU.allSatisfy { $0.count == 4 }
                  && $0.acrossV.count == 4 && $0.acrossV.allSatisfy { $0.count == 4 } }) else {
            throw failure(.invalidInput, "A PolySplines G2 cap needs three or more sectors other than four, each beside bicubic patches.")
        }
        // The rows fixed by the regular patches: q[k][i][j], i along u, j along v.
        var fixed: [Key: Point3D] = [:]
        let match = tolerance.distance * 1e-6
        func fix(_ key: Key, _ point: Point3D) throws {
            if let existing = fixed[key] {
                guard (existing - point).length <= match else {
                    throw failure(.invalidInput, "A PolySplines G2 cap's regular neighbours do not join smoothly.")
                }
                return
            }
            fixed[key] = point
        }
        for (k, sector) in sectors.enumerated() {
            // Beyond u = 1: each row j of the cap from the neighbour's curves along v at its first
            // three u columns, raised to degree m, carried back across the side.
            let alongV = (0..<3).map { a in elevated(sector.acrossU.map { $0[a] }, to: m) }
            for (i, row) in carriedBack(alongV, degree: m).enumerated() {
                for j in 0...m { try fix(Key(k, m - i, j), row[j]) }
            }
            let alongU = (0..<3).map { a in elevated(sector.acrossV[a], to: m) }
            for (j, column) in carriedBack(alongU, degree: m).enumerated() {
                for i in 0...m { try fix(Key(k, i, m - j), column[i]) }
            }
        }
        // The shared edges: q_k[i][0] is q_{k−1}[0][i], the vertex shared by all.
        func canonical(_ k: Int, _ i: Int, _ j: Int) -> Key {
            let k = ((k % n) + n) % n
            if i == 0, j == 0 { return Key(0, 0, 0) }
            if j == 0 { return Key((k + n - 1) % n, 0, i) }
            return Key(k, i, j)
        }
        for k in 0..<n {
            for i in (m - 2)...m {
                if let own = fixed[Key(k, i, 0)] { try fix(canonical(k, i, 0), own) }
            }
        }
        fixed[Key(0, 0, 0)] = apex
        var unknownIndex: [Key: Int] = [:]
        for k in 0..<n {
            for i in 0...m {
                for j in 0...m {
                    let key = canonical(k, i, j)
                    guard fixed[Key(k, i, j)] == nil, fixed[key] == nil, unknownIndex[key] == nil else { continue }
                    unknownIndex[key] = unknownIndex.count
                }
            }
        }
        let unknowns = unknownIndex.count
        guard unknowns > 0 else { throw failure(.invalidInput, "A PolySplines G2 cap has no free control points.") }
        func slot(_ k: Int, _ i: Int, _ j: Int) -> (index: Int?, point: Point3D?) {
            let own = Key(((k % n) + n) % n, i, j)
            if let point = fixed[own] { return (nil, point) }
            let key = canonical(k, i, j)
            if let point = fixed[key] { return (nil, point) }
            return (unknownIndex[key], nil)
        }
        // A derivative of q_k at (s, t) as a linear functional: coefficients on the unknowns and
        // the fixed points' part.
        func derivative(_ k: Int, _ s: Double, _ t: Double, _ ds: Int, _ dt: Int) -> (row: [Double], constant: Vector3D) {
            var row = Array(repeating: 0.0, count: unknowns)
            var constant = Vector3D.zero
            let bs = (0...m).map { bernsteinDerivative(m, $0, s, ds) }
            let bt = (0...m).map { bernsteinDerivative(m, $0, t, dt) }
            for i in 0...m where bs[i] != 0 {
                for j in 0...m where bt[j] != 0 {
                    let w = bs[i] * bt[j]
                    let (index, point) = slot(k, i, j)
                    if let index { row[index] += w } else if let point { constant = constant + (point - .origin) * w }
                }
            }
            return (row, constant)
        }
        func combine(_ terms: [(Double, (row: [Double], constant: Vector3D))]) -> (row: [Double], constant: Vector3D) {
            var row = Array(repeating: 0.0, count: unknowns)
            var constant = Vector3D.zero
            for (weight, term) in terms {
                for index in term.row.indices where term.row[index] != 0 { row[index] += weight * term.row[index] }
                constant = constant + term.constant * weight
            }
            return (row, constant)
        }
        let c = cos(2 * Double.pi / Double(n))
        let second = -6 * c * c / (1 + c)
        var constraints: [(row: [Double], constant: Vector3D)] = []
        let samples = m + 5
        for k in 0..<n {
            for l in 0..<samples {
                let u = 0.5 - 0.5 * cos(Double.pi * Double(l) / Double(samples - 1))
                let fade = (1 - u) * (1 - u) * (1 - u)
                let (b, d, e) = (2 * c * fade, second * fade, second * fade)
                constraints.append(combine([
                    (1, derivative(k + 1, u, 0, 0, 1)), (1, derivative(k, 0, u, 1, 0)), (-b, derivative(k, 0, u, 0, 1)),
                ]))
                constraints.append(combine([
                    (1, derivative(k + 1, u, 0, 0, 2)), (-1, derivative(k, 0, u, 2, 0)), (2 * b, derivative(k, 0, u, 1, 1)),
                    (-b * b, derivative(k, 0, u, 0, 2)), (-2 * d, derivative(k, 0, u, 0, 1)), (-2 * e, derivative(k, 0, u, 1, 0)),
                ]))
            }
        }
        // Thin-plate energy, by eight-point Gauss–Legendre over each sector.
        var energy: [(row: [Double], constant: Vector3D)] = []
        for k in 0..<n {
            for (s, ws) in Self.gauss {
                for (t, wt) in Self.gauss {
                    for (ds, dt, weight) in [(2, 0, 1.0), (1, 1, 2.0), (0, 2, 1.0)] {
                        let term = derivative(k, s, t, ds, dt)
                        let scale = (ws * wt * weight).squareRoot()
                        energy.append((term.row.map { $0 * scale }, term.constant * scale))
                    }
                }
            }
        }
        let solution = try constrainedLeastSquares(constraints: constraints, energy: energy, unknowns: unknowns)
        // Every condition must hold to roundoff of the cap's size.
        let points = Array(fixed.values) + [apex]
        let extent = points.reduce(0.0) { max($0, ($1 - apex).length) }
        let allowance = max(extent, tolerance.distance) * 1e-9
        for constraint in constraints {
            var value = constraint.constant
            for index in constraint.row.indices where constraint.row[index] != 0 {
                value = value + solution[index] * constraint.row[index]
            }
            guard value.length <= allowance else {
                throw failure(.singularSystem, "A PolySplines G2 cap cannot meet its continuity conditions.")
            }
        }
        return (0..<n).map { k in
            (0...m).map { j in
                (0...m).map { i in
                    let (index, point) = slot(k, i, j)
                    if let point { return point }
                    return .origin + solution[index ?? 0]
                }
            }
        }
    }

    // MARK: - Linear algebra

    /// Minimises the energy rows' squares subject to the constraint rows (each `row · x + constant
    /// = 0` per coordinate): the constraints' solutions as a particular one plus their null space,
    /// read from a column-pivoted QR of the constraints' transpose, then the energy over that space.
    private func constrainedLeastSquares(constraints: [(row: [Double], constant: Vector3D)],
                                         energy: [(row: [Double], constant: Vector3D)], unknowns: Int) throws -> [Vector3D] {
        let count = constraints.count
        var transpose = Array(repeating: 0.0, count: unknowns * count)
        for (r, constraint) in constraints.enumerated() {
            for u in 0..<unknowns { transpose[u * count + r] = constraint.row[u] }
        }
        let qr = try SurfaceFittingQR(coefficients: transpose, rows: unknowns, columns: count,
                                      relativeRankTolerance: 1e-11, maximumElements: 1 << 22)
        let rank = qr.rank
        // Constraint perm[k] reads R[0...k][k] · y = −constant, y the first `rank` coordinates of Qᵀx.
        var y = Array(repeating: Vector3D.zero, count: unknowns)
        for k in 0..<rank {
            var value = constraints[qr.permutation[k]].constant * -1
            for i in 0..<k { value = value - y[i] * (qr.scale * (try qr.upperCoefficient(row: i, column: k))) }
            y[k] = value * (1 / (qr.scale * (try qr.upperCoefficient(row: k, column: k))))
        }
        func applyingQ(_ vectors: [Vector3D]) throws -> [Vector3D] {
            let (x, yy, z) = (try qr.applyingQ(to: vectors.map(\.x)), try qr.applyingQ(to: vectors.map(\.y)),
                              try qr.applyingQ(to: vectors.map(\.z)))
            return (0..<unknowns).map { Vector3D(x: x[$0], y: yy[$0], z: z[$0]) }
        }
        let particular = try applyingQ(y)
        let freedom = unknowns - rank
        guard freedom > 0 else { return particular }
        var nullSpace: [[Double]] = []
        for column in rank..<unknowns {
            var unit = Array(repeating: 0.0, count: unknowns)
            unit[column] = 1
            nullSpace.append(try qr.applyingQ(to: unit))
        }
        // The energy over x = particular + Z w.
        var reduced = Array(repeating: 0.0, count: energy.count * freedom)
        var rightHandSide = Array(repeating: Vector3D.zero, count: energy.count)
        for (r, row) in energy.enumerated() {
            var offset = row.constant
            for u in 0..<unknowns where row.row[u] != 0 { offset = offset + particular[u] * row.row[u] }
            rightHandSide[r] = offset * -1
            for f in 0..<freedom {
                var value = 0.0
                for u in 0..<unknowns where row.row[u] != 0 { value += row.row[u] * nullSpace[f][u] }
                reduced[r * freedom + f] = value
            }
        }
        let fit = try SurfaceFittingQR(coefficients: reduced, rows: energy.count, columns: freedom,
                                       relativeRankTolerance: 1e-12, maximumElements: 1 << 22)
        let (wx, wy, wz) = (try fit.solveFullRankLeastSquares(rightHandSide.map(\.x)),
                            try fit.solveFullRankLeastSquares(rightHandSide.map(\.y)),
                            try fit.solveFullRankLeastSquares(rightHandSide.map(\.z)))
        return (0..<unknowns).map { u in
            var value = particular[u]
            for f in 0..<freedom { value = value + Vector3D(x: wx[f], y: wy[f], z: wz[f]) * nullSpace[f][u] }
            return value
        }
    }

    // MARK: - Bézier helpers

    private struct Key: Hashable {
        let k: Int, i: Int, j: Int
        init(_ k: Int, _ i: Int, _ j: Int) { (self.k, self.i, self.j) = (k, i, j) }
    }

    /// A cubic Bézier curve's control points raised to `degree`.
    private func elevated(_ points: [Point3D], to degree: Int) -> [Point3D] {
        var result = points
        while result.count - 1 < degree {
            let p = Double(result.count - 1)
            var next = [result[0]]
            for i in 1..<result.count {
                let a = Double(i) / (p + 1)
                next.append(.origin + (result[i - 1] - .origin) * a + (result[i] - .origin) * (1 - a))
            }
            next.append(result[result.count - 1])
            result = next
        }
        return result
    }

    /// The three rows of a degree-`degree` patch next to a side sharing the neighbour's position
    /// and first two cross derivatives there, from the neighbour's first three rows away from the
    /// side (each raised to `degree`): the row on the side, then the next two inward.
    private func carriedBack(_ rows: [[Point3D]], degree m: Int) -> [[Point3D]] {
        let count = rows[0].count
        var result: [[Point3D]] = [[], [], []]
        for j in 0..<count {
            let (r0, r1, r2) = (rows[0][j] - .origin, rows[1][j] - .origin, rows[2][j] - .origin)
            // The neighbour's parameter runs on from the cap's across the side, so the cap's end
            // derivatives there are the neighbour's start derivatives.
            let first = (r1 - r0) * 3
            let second = (r2 - r1 * 2 + r0) * 6
            let side = r0
            let next = side - first * (1 / Double(m))
            let after = next * 2 - side + second * (1 / Double(m * (m - 1)))
            result[0].append(.origin + side)
            result[1].append(.origin + next)
            result[2].append(.origin + after)
        }
        return result
    }

    /// The `order`-th derivative of the Bernstein polynomial B(m, i) at t.
    private func bernsteinDerivative(_ m: Int, _ i: Int, _ t: Double, _ order: Int) -> Double {
        guard i >= 0, i <= m else { return 0 }
        if order == 0 {
            return binomial(m, i) * pow(t, Double(i)) * pow(1 - t, Double(m - i))
        }
        guard m > 0 else { return 0 }
        return Double(m) * (bernsteinDerivative(m - 1, i - 1, t, order - 1) - bernsteinDerivative(m - 1, i, t, order - 1))
    }

    private func binomial(_ n: Int, _ k: Int) -> Double {
        var value = 1.0
        for i in 0..<k { value = value * Double(n - i) / Double(i + 1) }
        return value
    }

    private static let gauss: [(Double, Double)] = {
        let nodes = [-0.9602898564975363, -0.7966664774136267, -0.5255324099163290, -0.1834346424956498,
                     0.1834346424956498, 0.5255324099163290, 0.7966664774136267, 0.9602898564975363]
        let weights = [0.1012285362903763, 0.2223810344533745, 0.3137066458778873, 0.3626837833783620,
                       0.3626837833783620, 0.3137066458778873, 0.2223810344533745, 0.1012285362903763]
        return zip(nodes, weights).map { (0.5 * ($0 + 1), 0.5 * $1) }
    }()

    private func failure(_ code: KernelErrorCode, _ message: String) -> KernelError {
        KernelError(phase: .evaluation, code: code, tolerance: tolerance, message: message)
    }
}
