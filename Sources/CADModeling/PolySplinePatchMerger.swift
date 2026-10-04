import Foundation
import CADCore
import CADGeometry
import CADIR

/// Merge Patches over a general PolySplines network: the bicubic patches joined into rectangular
/// blocks, each one B-spline surface with one control grid (Plasticity's merged faces).
///
/// A block grows from a patch along its u and v directions over patch edges whose ends are both
/// regular vertices (four patches around an inner vertex, two along the boundary), so blocks stop
/// at extraordinary vertices where the patches meet only nearly tangent. A block's patches are
/// laid side by side with knots of multiplicity three at their joints, the exact union of the
/// patches; each joint knot is then removed as far as the surface stays within a small fraction
/// of the modeling distance (Piegl and Tiller's knot removal), which a regular region, the uniform
/// cubic B-spline exactly, allows down to a simple knot. A G2 cap's patch (degree eight) is a
/// block of its own: blocks of bicubic patches stop at it.
package struct PolySplinePatchMerger {
    /// One merged face: its surface over u ∈ [0, columns], v ∈ [0, rows] and its boundary as the
    /// patch edges it is made of, counterclockwise, each with the parameter run it covers.
    package struct Block {
        package struct Side {
            /// The patch edge's Bézier control points, in the block's counterclockwise order.
            package let curve: [Point3D]
            package let parameterCurve: SurfaceParameterCurve
        }

        package let surface: BSplineSurface3D
        package let sides: [Side]
    }

    private let tolerance: ModelingTolerance

    package init(tolerance: ModelingTolerance) {
        self.tolerance = tolerance
    }

    package func blocks(of network: PolySplineSubdivisionPatchBuilder.Network) throws -> [Block] {
        let patches = network.patches
        // Directed edge → the patch traversing it counterclockwise.
        var owner: [DirectedEdge: Int] = [:]
        var patchesAt: [Int: Int] = [:]
        var uses: [UndirectedEdge: Int] = [:]
        for (index, patch) in patches.enumerated() {
            for k in 0..<4 {
                let (a, b) = (patch.corners[k], patch.corners[(k + 1) % 4])
                owner[DirectedEdge(from: a, to: b)] = index
                uses[UndirectedEdge(a, b), default: 0] += 1
            }
            for corner in patch.corners { patchesAt[corner, default: 0] += 1 }
        }
        let boundaryVertices = Set(uses.filter { $0.value == 1 }.keys.flatMap { [$0.a, $0.b] })
        func isRegular(_ vertex: Int) -> Bool {
            patchesAt[vertex] == (boundaryVertices.contains(vertex) ? 2 : 4)
        }
        // A patch placed in a block: its index and its corners rotated so corner 0 is at the
        // block's (u, v) origin side.
        struct Placed { let index: Int; let start: Int }
        func corners(_ placed: Placed) -> [Int] {
            (0..<4).map { patches[placed.index].corners[(placed.start + $0) % 4] }
        }
        // The neighbour across a placed patch's +u side (corners 1→2) or +v side (3→2), turned to
        // continue the grid, when that side may be merged across.
        func neighbour(_ placed: Placed, alongU: Bool) -> Placed? {
            let c = corners(placed)
            let (a, b) = alongU ? (c[1], c[2]) : (c[3], c[2])
            guard patches[placed.index].isBicubic, isRegular(a), isRegular(b),
                  let index = owner[alongU ? DirectedEdge(from: b, to: a) : DirectedEdge(from: a, to: b)],
                  patches[index].isBicubic, let k = patches[index].corners.firstIndex(of: a) else { return nil }
            // +u: the neighbour's corner 0 is our corner 1 (its 3 our 2); +v: its 0 is our 3 (its 1 our 2).
            let placedNeighbour = Placed(index: index, start: k)
            let n = corners(placedNeighbour)
            return alongU ? (n[3] == b ? placedNeighbour : nil) : (n[1] == b ? placedNeighbour : nil)
        }
        func backward(_ placed: Placed, alongU: Bool) -> Placed? {
            let c = corners(placed)
            let (a, b) = alongU ? (c[0], c[3]) : (c[0], c[1])
            guard patches[placed.index].isBicubic, isRegular(a), isRegular(b),
                  let index = owner[alongU ? DirectedEdge(from: a, to: b) : DirectedEdge(from: b, to: a)],
                  patches[index].isBicubic else { return nil }
            // −u: the neighbour's corner 1 is our 0 and its 2 our 3; −v: its 3 is our 0, its 2 our 1.
            guard let k = patches[index].corners.firstIndex(of: a) else { return nil }
            let start = (k + (alongU ? 3 : 1)) % 4
            let placedNeighbour = Placed(index: index, start: start)
            let n = corners(placedNeighbour)
            return alongU ? (n[1] == a && n[2] == b ? placedNeighbour : nil) : (n[3] == a && n[2] == b ? placedNeighbour : nil)
        }

        var assigned = Set<Int>()
        var blocks: [Block] = []
        // Seeds are taken until every patch is placed: a block grown round a closed band may leave
        // out the very patch it was seeded from.
        while let seed = patches.indices.first(where: { assigned.contains($0) == false }) {
            guard patches[seed].isBicubic else {
                blocks.append(try single(patches[seed]))
                assigned.insert(seed)
                continue
            }
            // Walk back to the block's corner, then grow the first row along u and further rows along v.
            var origin = Placed(index: seed, start: 0)
            var visited: Set<Int> = [seed]
            for alongU in [true, false] {
                while let previous = backward(origin, alongU: alongU), assigned.contains(previous.index) == false,
                      visited.insert(previous.index).inserted {
                    origin = previous
                }
            }
            var rows: [[Placed]] = []
            var taken = Set<Int>()
            var row = [origin]
            taken.insert(origin.index)
            // A row running round a closed band stops short of closing: its last patch's far side
            // would be its first patch's near side, one edge bounding the block twice.
            while let next = neighbour(row[row.count - 1], alongU: true), assigned.contains(next.index) == false,
                  taken.contains(next.index) == false, neighbour(next, alongU: true)?.index != row[0].index {
                row.append(next)
                taken.insert(next.index)
            }
            rows.append(row)
            growing: while true {
                var nextRow: [Placed] = []
                for (column, placed) in rows[rows.count - 1].enumerated() {
                    guard let above = neighbour(placed, alongU: false), assigned.contains(above.index) == false,
                          taken.contains(above.index) == false, nextRow.contains(where: { $0.index == above.index }) == false else { break growing }
                    if column > 0 {
                        // The row must run on as a row: each patch the +u neighbour of the one before.
                        guard let along = neighbour(nextRow[column - 1], alongU: true), along.index == above.index,
                              along.start == above.start else { break growing }
                    }
                    nextRow.append(above)
                }
                // Likewise rows stacking round a band stop before the block closes on its first row.
                if let beyond = neighbour(nextRow[0], alongU: false), beyond.index == rows[0][0].index { break growing }
                rows.append(nextRow)
                taken.formUnion(nextRow.map(\.index))
            }
            assigned.formUnion(taken)
            blocks.append(try block(rows.map { $0.map { (net(patches[$0.index].net, rotatedBy: $0.start)) } }))
        }
        return blocks
    }

    // MARK: - Blocks

    /// The patch's net turned so corner `start` is its (0, 0): each turn takes the old (u = 1,
    /// v = 0) corner to the origin, the old +v becoming +u.
    private func net(_ net: [[Point3D]], rotatedBy start: Int) -> [[Point3D]] {
        var result = net
        for _ in 0..<start {
            let old = result
            result = (0..<4).map { j in (0..<4).map { i in old[i][3 - j] } }
        }
        return result
    }

    /// A patch as its own block: its Bézier surface and its four sides.
    private func single(_ patch: PolySplineSubdivisionPatchBuilder.Patch) throws -> Block {
        let degree = patch.net.count - 1
        let knots = Array(repeating: 0.0, count: degree + 1) + Array(repeating: 1.0, count: degree + 1)
        let surface = BSplineSurface3D(uDegree: degree, vDegree: degree, uKnots: knots, vKnots: knots, controlPoints: patch.net)
        try surface.validate(tolerance: tolerance)
        return Block(surface: surface, sides: [
            .init(curve: patch.sides[0], parameterCurve: .constantV(v: 0, uStart: 0, uEnd: 1)),
            .init(curve: patch.sides[1], parameterCurve: .constantU(u: 1, vStart: 0, vEnd: 1)),
            .init(curve: patch.sides[2].reversed(), parameterCurve: .constantV(v: 1, uStart: 1, uEnd: 0)),
            .init(curve: patch.sides[3].reversed(), parameterCurve: .constantU(u: 0, vStart: 1, vEnd: 0)),
        ])
    }

    /// One block's surface: the patches' nets laid side by side (shared rows once) with triple
    /// joint knots, then every joint knot removed as far as the surface allows.
    private func block(_ nets: [[[[Point3D]]]]) throws -> Block {
        let (rows, columns) = (nets.count, nets[0].count)
        var grid = Array(repeating: Array(repeating: Point3D.origin, count: 3 * columns + 1), count: 3 * rows + 1)
        let match = tolerance.distance * 1e-3
        for r in 0..<rows {
            for c in 0..<columns {
                for j in 0..<4 {
                    for i in 0..<4 {
                        let (row, column) = (3 * r + j, 3 * c + i)
                        let point = nets[r][c][j][i]
                        if (j == 0 && r > 0) || (i == 0 && c > 0) {
                            guard (grid[row][column] - point).length <= match else {
                                throw KernelError(phase: .evaluation, code: .invalidInput, tolerance: tolerance,
                                                  message: "PolySplines' merged patches do not share their boundary.")
                            }
                        }
                        grid[row][column] = point
                    }
                }
            }
        }
        func knots(_ count: Int) -> [Double] {
            [0, 0, 0, 0] + (1..<count).flatMap { Array(repeating: Double($0), count: 3) } + Array(repeating: Double(count), count: 4)
        }
        var surface = BSplineSurface3D(uDegree: 3, vDegree: 3, uKnots: knots(columns), vKnots: knots(rows), controlPoints: grid)
        // Sides, counterclockwise: bottom (+u), right (+v), top (−u), left (−v), each patch edge one side.
        var sides: [Block.Side] = []
        for c in 0..<columns {
            sides.append(.init(curve: nets[0][c][0], parameterCurve: .constantV(v: 0, uStart: Double(c), uEnd: Double(c + 1))))
        }
        for r in 0..<rows {
            sides.append(.init(curve: nets[r][columns - 1].map { $0[3] },
                               parameterCurve: .constantU(u: Double(columns), vStart: Double(r), vEnd: Double(r + 1))))
        }
        for c in (0..<columns).reversed() {
            sides.append(.init(curve: nets[rows - 1][c][3].reversed(),
                               parameterCurve: .constantV(v: Double(rows), uStart: Double(c + 1), uEnd: Double(c))))
        }
        for r in (0..<rows).reversed() {
            sides.append(.init(curve: nets[r][0].map { $0[0] }.reversed(),
                               parameterCurve: .constantU(u: 0, vStart: Double(r + 1), vEnd: Double(r))))
        }
        surface = removingJointKnots(surface, columns: columns, rows: rows)
        try surface.validate(tolerance: tolerance)
        return Block(surface: surface, sides: sides)
    }

    /// The surface with each joint knot removed as often as every row (or column) allows within
    /// a thousandth of the modeling distance.
    private func removingJointKnots(_ surface: BSplineSurface3D, columns: Int, rows: Int) -> BSplineSurface3D {
        var result = surface
        let allowance = tolerance.distance * 1e-3
        for joint in 1..<max(columns, 1) {
            while let removed = removingOnce(Double(joint), from: result.uKnots, rows: result.controlPoints, allowance: allowance) {
                result.uKnots = removed.knots
                result.controlPoints = removed.rows
            }
        }
        for joint in 1..<max(rows, 1) {
            let columnsOfPoints = (0..<result.controlPoints[0].count).map { i in result.controlPoints.map { $0[i] } }
            var columnsNow = columnsOfPoints
            var knots = result.vKnots
            while let removed = removingOnce(Double(joint), from: knots, rows: columnsNow, allowance: allowance) {
                knots = removed.knots
                columnsNow = removed.rows
            }
            result.vKnots = knots
            result.controlPoints = (0..<columnsNow[0].count).map { j in columnsNow.map { $0[j] } }
        }
        result.weights = result.controlPoints.map { Array(repeating: 1.0, count: $0.count) }
        return result
    }

    /// One occurrence of knot `u` removed from every curve in `rows` (cubic, non-rational), or
    /// nil when it is not a knot there or some curve would move by more than `allowance`.
    private func removingOnce(_ u: Double, from knots: [Double], rows: [[Point3D]], allowance: Double) -> (knots: [Double], rows: [[Point3D]])? {
        let p = 3
        guard let r = knots.lastIndex(of: u) else { return nil }
        let s = knots.filter { $0 == u }.count
        guard s >= 1 else { return nil }
        let first = r - p, last = r - s
        guard first >= 1 else { return nil }
        let off = first - 1
        var updated: [[Point3D]] = []
        for points in rows {
            let n = points.count - 1
            var temp = Array(repeating: Point3D.origin, count: last - off + 2)
            temp[0] = points[off]
            temp[last + 1 - off] = points[last + 1]
            var (i, j, ii, jj) = (first, last, 1, last - off)
            while j - i > 0 {
                let alfi = (u - knots[i]) / (knots[i + p + 1] - knots[i])
                let alfj = (u - knots[j]) / (knots[j + p + 1] - knots[j])
                temp[ii] = .origin + ((points[i] - .origin) - (temp[ii - 1] - .origin) * (1 - alfi)) * (1 / alfi)
                temp[jj] = .origin + ((points[j] - .origin) - (temp[jj + 1] - .origin) * alfj) * (1 / (1 - alfj))
                i += 1; ii += 1; j -= 1; jj -= 1
            }
            if j - i < 0 {
                guard (temp[ii - 1] - temp[jj + 1]).length <= allowance else { return nil }
            } else {
                let alfi = (u - knots[i]) / (knots[i + p + 1] - knots[i])
                let blended = Point3D.origin + (temp[ii + 1] - .origin) * alfi + (temp[ii - 1] - .origin) * (1 - alfi)
                guard (points[i] - blended).length <= allowance else { return nil }
            }
            var result = points
            (i, j) = (first, last)
            while j - i > 0 {
                result[i] = temp[i - off]
                result[j] = temp[j - off]
                i += 1; j -= 1
            }
            // The point at fout = (2r − s − p) / 2 goes.
            let fout = (2 * r - s - p) / 2
            result.remove(at: fout)
            guard result.count == n else { return nil }
            updated.append(result)
        }
        var newKnots = knots
        newKnots.remove(at: r)
        return (newKnots, updated)
    }

    private struct DirectedEdge: Hashable { let from: Int; let to: Int }
    private struct UndirectedEdge: Hashable {
        let a: Int, b: Int
        init(_ x: Int, _ y: Int) { (a, b) = x < y ? (x, y) : (y, x) }
    }
}
