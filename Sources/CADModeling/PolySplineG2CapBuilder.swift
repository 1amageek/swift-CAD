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
        try Task.checkCancellation()
        let n = sectors.count
        let m = Self.degree
        guard n >= 3, n != 4,
              sectors.allSatisfy({ $0.acrossU.count == 4 && $0.acrossU.allSatisfy { $0.count == 4 }
                  && $0.acrossV.count == 4 && $0.acrossV.allSatisfy { $0.count == 4 } }) else {
            throw failure(.invalidInput, "A PolySplines G2 cap needs three or more sectors other than four, each beside bicubic patches.")
        }
        let sectorControlCount = try checkedProduct(n, (m + 1) * (m + 1), message: "A PolySplines G2 cap exceeded its sector control-point range.")
        guard sectorControlCount <= Self.maximumMatrixElements else {
            throw failure(.resourceLimitExceeded, "A PolySplines G2 cap exceeded its sector control-point budget.")
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
            try Task.checkCancellation()
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
        let samples = m + 5
        let constraintCount = try checkedProduct(n, samples * 2, message: "A PolySplines G2 cap exceeded its constraint count range.")
        guard constraintCount <= Self.maximumMatrixElements else {
            throw failure(.resourceLimitExceeded, "A PolySplines G2 cap exceeded its constraint storage budget.")
        }
        _ = try checkedMatrixElementCountForAdmission(unknowns, constraintCount)
        var constraints: [(row: [Double], constant: Vector3D)] = []
        constraints.reserveCapacity(constraintCount)
        for k in 0..<n {
            try Task.checkCancellation()
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
        let energyCount = try checkedProduct(n, Self.energyRowsPerSector, message: "A PolySplines G2 cap exceeded its energy row count range.")
        guard energyCount <= Self.maximumMatrixElements else {
            throw failure(.resourceLimitExceeded, "A PolySplines G2 cap exceeded its energy storage budget.")
        }
        _ = try checkedMatrixElementCountForAdmission(unknowns, energyCount)
        var energy: [(row: [Double], constant: Vector3D)] = []
        energy.reserveCapacity(energyCount)
        for k in 0..<n {
            try Task.checkCancellation()
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
        try Task.checkCancellation()
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
        try Task.checkCancellation()
        let nets = (0..<n).map { k in
            (0...m).map { j in
                (0...m).map { i in
                    let (index, point) = slot(k, i, j)
                    if let point { return point }
                    return .origin + solution[index ?? 0]
                }
            }
        }
        try certifyAdmission(nets: nets, sectors: sectors, apex: apex, c: c, second: second, allowance: allowance)
        return nets
    }

    private static let maximumMatrixElements = 1 << 22
    private static let energyRowsPerSector = 8 * 8 * 3

    private func checkedProduct(_ first: Int, _ second: Int, message: String) throws -> Int {
        let result = first.multipliedReportingOverflow(by: second)
        guard result.overflow == false else { throw failure(.resourceLimitExceeded, message) }
        return result.partialValue
    }

    /// The matrix element budget used by every allocation in the cap's admission and QR path.
    /// This is package-visible only so the focused admission tests exercise the production guard.
    package func checkedMatrixElementCountForAdmission(_ first: Int, _ second: Int) throws -> Int {
        let result = first.multipliedReportingOverflow(by: second)
        guard result.overflow == false, result.partialValue <= Self.maximumMatrixElements else {
            throw failure(.resourceLimitExceeded, "A PolySplines G2 cap exceeded its matrix storage budget.")
        }
        return result.partialValue
    }

    // MARK: - Admission

    private typealias Interval = OutwardScalarInterval
    private typealias IntervalVector = IntervalVector3DBounds

    private func certifyAdmission(
        nets: [[[Point3D]]],
        sectors: [Sector],
        apex: Point3D,
        c: Double,
        second: Double,
        allowance: Double
    ) throws {
        try Task.checkCancellation()
        let n = nets.count
        let match = tolerance.distance * 1e-6
        let fade: [Interval] = [.exact(1), .exact(0), .exact(0), .exact(0)]
        let b = scale(fade, by: 2 * c)
        let d = scale(fade, by: second)
        let e = d
        for k in 0..<n {
            try Task.checkCancellation()
            let next = nets[(k + 1) % n]
            let current = nets[k]
            let g1 = add(
                derivative(next, fixingFirst: false, atUpper: false, firstOrder: 0, secondOrder: 1),
                derivative(current, fixingFirst: true, atUpper: false, firstOrder: 1, secondOrder: 0)
            )
            let g1Residual = subtract(g1, multiply(
                derivative(current, fixingFirst: true, atUpper: false, firstOrder: 0, secondOrder: 1),
                b
            ))
            try certifyAdmissionResidual(g1Residual, allowance: allowance, message: "A PolySplines G2 cap failed its whole-edge G1 enclosure.")

            var g2 = subtract(
                derivative(next, fixingFirst: false, atUpper: false, firstOrder: 0, secondOrder: 2),
                derivative(current, fixingFirst: true, atUpper: false, firstOrder: 2, secondOrder: 0)
            )
            g2 = add(g2, multiply(
                derivative(current, fixingFirst: true, atUpper: false, firstOrder: 1, secondOrder: 1),
                scale(b, by: 2)
            ))
            g2 = subtract(g2, multiply(
                derivative(current, fixingFirst: true, atUpper: false, firstOrder: 0, secondOrder: 2),
                multiply(b, b)
            ))
            g2 = subtract(g2, multiply(
                derivative(current, fixingFirst: true, atUpper: false, firstOrder: 0, secondOrder: 1),
                scale(d, by: 2)
            ))
            g2 = subtract(g2, multiply(
                derivative(current, fixingFirst: true, atUpper: false, firstOrder: 1, secondOrder: 0),
                scale(e, by: 2)
            ))
            try certifyAdmissionResidual(g2, allowance: allowance, message: "A PolySplines G2 cap failed its whole-edge G2 enclosure.")

            try certifyAdmissionRegularity(current, fixingFirst: false, atUpper: false)
            try certifyAdmissionRegularity(current, fixingFirst: true, atUpper: false)
            try certifyAdmissionRegularity(current, fixingFirst: false, atUpper: true)
            try certifyAdmissionRegularity(current, fixingFirst: true, atUpper: true)
            try certifyTaylorBoundary(cap: current, neighbor: sectors[k].acrossU, fixingFirst: true, match: match)
            try certifyTaylorBoundary(cap: current, neighbor: sectors[k].acrossV, fixingFirst: false, match: match)
        }
        _ = apex
    }

    package func certifyAdmissionResidual(
        _ residual: [IntervalVector3DBounds],
        allowance: Double,
        message: String = "A PolySplines G2 cap failed its whole-edge residual enclosure."
    ) throws {
        let bound = residual.reduce(0.0) { max($0, $1.lengthUpperBound) }
        guard bound.isFinite else { throw failure(.resourceLimitExceeded, "A PolySplines G2 cap residual exceeded finite arithmetic range.") }
        guard bound <= allowance else { throw failure(.singularSystem, message) }
    }

    package func certifyAdmissionRegularity(
        _ net: [[Point3D]],
        fixingFirst: Bool,
        atUpper: Bool
    ) throws {
        let tangentU = derivative(net, fixingFirst: fixingFirst, atUpper: atUpper, firstOrder: 1, secondOrder: 0)
        let tangentV = derivative(net, fixingFirst: fixingFirst, atUpper: atUpper, firstOrder: 0, secondOrder: 1)
        let cross = crossProduct(tangentU, tangentV)
        let tangentUBounds = bounds(tangentU)
        let tangentVBounds = bounds(tangentV)
        let crossBounds = bounds(cross)
        let tangentULower = tangentUBounds.lengthLowerBound
        let tangentVLower = tangentVBounds.lengthLowerBound
        let tangentUUpper = tangentUBounds.lengthUpperBound
        let tangentVUpper = tangentVBounds.lengthUpperBound
        let crossLower = crossBounds.lengthLowerBound
        guard tangentULower > tolerance.distance,
              tangentVLower > tolerance.distance,
              tangentUUpper.isFinite,
              tangentVUpper.isFinite,
              crossLower.isFinite else {
            throw failure(.singularSystem, "A PolySplines G2 cap has an unproved tangent regularity interval.")
        }
        let sineTolerance = max(
            sin(min(tolerance.angle, Double.pi * 0.5)),
            tolerance.relative,
            Double.ulpOfOne * 256
        )
        guard crossLower > sineTolerance * tangentUUpper * tangentVUpper else {
            throw failure(.singularSystem, "A PolySplines G2 cap has an unproved surface normal interval.")
        }
    }

    private func certifyTaylorBoundary(
        cap: [[Point3D]],
        neighbor: [[Point3D]],
        fixingFirst: Bool,
        match: Double
    ) throws {
        for order in 0...2 {
            // The Taylor data are normal derivatives: acrossU fixes the first parameter and
            // acrossV fixes the second. The remaining parameter is the boundary curve.
            let firstOrder = fixingFirst ? order : 0
            let secondOrder = fixingFirst ? 0 : order
            let capBoundary = derivative(cap, fixingFirst: fixingFirst, atUpper: true, firstOrder: firstOrder, secondOrder: secondOrder)
            let neighborBoundary = derivative(neighbor, fixingFirst: fixingFirst, atUpper: false, firstOrder: firstOrder, secondOrder: secondOrder)
            let residual = subtract(capBoundary, neighborBoundary)
            let bound = residual.reduce(0.0) { max($0, $1.lengthUpperBound) }
            guard bound.isFinite else { throw failure(.resourceLimitExceeded, "A PolySplines G2 cap Taylor boundary exceeded finite arithmetic range.") }
            guard bound <= match else { throw failure(.invalidInput, "A PolySplines G2 cap Taylor boundary exceeded its neighbor rounding allowance.") }
        }
    }

    private func derivative(
        _ net: [[Point3D]],
        fixingFirst: Bool,
        atUpper: Bool,
        firstOrder: Int,
        secondOrder: Int
    ) -> [IntervalVector] {
        var values = net.map { $0.map(intervalVector) }
        // Nets are stored as [v][u]. `firstOrder` is the first (u) parameter and
        // `secondOrder` is the second (v) parameter, matching the solver equations above.
        for _ in 0..<firstOrder {
            let degree = values[0].count - 1
            values = values.map { row in
                (0..<degree).map { column in
                    subtract(row[column + 1], row[column], scale: Double(degree))
                }
            }
        }
        for _ in 0..<secondOrder {
            let degree = values.count - 1
            values = (0..<degree).map { row in
                values[row + 1].indices.map { column in
                    subtract(values[row + 1][column], values[row][column], scale: Double(degree))
                }
            }
        }
        if fixingFirst {
            let column = atUpper ? values[0].count - 1 : 0
            return values.map { $0[column] }
        }
        return values[atUpper ? values.count - 1 : 0]
    }

    private func intervalVector(_ point: Point3D) -> IntervalVector {
        IntervalVector(x: .exact(point.x), y: .exact(point.y), z: .exact(point.z))
    }

    private func bounds(_ values: [IntervalVector]) -> IntervalVector {
        IntervalVector(
            x: .enclosing(values.map(\.x)),
            y: .enclosing(values.map(\.y)),
            z: .enclosing(values.map(\.z))
        )
    }

    private func subtract(_ lhs: IntervalVector, _ rhs: IntervalVector) -> IntervalVector {
        IntervalVector(x: lhs.x - rhs.x, y: lhs.y - rhs.y, z: lhs.z - rhs.z)
    }

    private func subtract(_ lhs: IntervalVector, _ rhs: IntervalVector, scale: Double) -> IntervalVector {
        let factor = Interval(scale)
        return IntervalVector(x: (lhs.x - rhs.x) * factor, y: (lhs.y - rhs.y) * factor, z: (lhs.z - rhs.z) * factor)
    }

    private func add(_ lhs: IntervalVector, _ rhs: IntervalVector) -> IntervalVector {
        IntervalVector(x: lhs.x + rhs.x, y: lhs.y + rhs.y, z: lhs.z + rhs.z)
    }

    private func scale(_ value: IntervalVector, by factor: Interval) -> IntervalVector {
        IntervalVector(x: value.x * factor, y: value.y * factor, z: value.z * factor)
    }

    private func scale(_ values: [IntervalVector], by factor: Double) -> [IntervalVector] {
        let scalar = Interval(factor)
        return values.map { scale($0, by: scalar) }
    }

    private func scale(_ values: [Interval], by factor: Double) -> [Interval] {
        let scalar = Interval(factor)
        return values.map { $0 * scalar }
    }

    private func add(_ lhs: [IntervalVector], _ rhs: [IntervalVector]) -> [IntervalVector] {
        let degree = max(lhs.count, rhs.count) - 1
        let first = elevated(lhs, to: degree)
        let second = elevated(rhs, to: degree)
        return zip(first, second).map(add)
    }

    private func subtract(_ lhs: [IntervalVector], _ rhs: [IntervalVector]) -> [IntervalVector] {
        let degree = max(lhs.count, rhs.count) - 1
        let first = elevated(lhs, to: degree)
        let second = elevated(rhs, to: degree)
        return zip(first, second).map(subtract)
    }

    private func subtract(_ lhs: [Interval], _ rhs: [Interval]) -> [Interval] {
        let degree = max(lhs.count, rhs.count) - 1
        let first = elevated(lhs, to: degree)
        let second = elevated(rhs, to: degree)
        return zip(first, second).map { $0.0 - $0.1 }
    }

    private func multiply(_ values: [IntervalVector], _ scalars: [Interval]) -> [IntervalVector] {
        let degree = values.count + scalars.count - 2
        var result = Array(repeating: IntervalVector(x: .exact(0), y: .exact(0), z: .exact(0)), count: degree + 1)
        for i in values.indices {
            for j in scalars.indices {
                let coefficient = productCoefficient(values.count - 1, i, scalars.count - 1, j)
                result[i + j] = add(result[i + j], scale(values[i], by: coefficient * scalars[j]))
            }
        }
        return result
    }

    private func multiply(_ lhs: [Interval], _ rhs: [Interval]) -> [Interval] {
        let degree = lhs.count + rhs.count - 2
        var result = Array(repeating: Interval.exact(0), count: degree + 1)
        for i in lhs.indices {
            for j in rhs.indices {
                result[i + j] = result[i + j] + lhs[i] * rhs[j] * productCoefficient(lhs.count - 1, i, rhs.count - 1, j)
            }
        }
        return result
    }

    private func crossProduct(_ lhs: [IntervalVector], _ rhs: [IntervalVector]) -> [IntervalVector] {
        let x = subtract(multiply(lhs.map(\.y), rhs.map(\.z)), multiply(lhs.map(\.z), rhs.map(\.y)))
        let y = subtract(multiply(lhs.map(\.z), rhs.map(\.x)), multiply(lhs.map(\.x), rhs.map(\.z)))
        let z = subtract(multiply(lhs.map(\.x), rhs.map(\.y)), multiply(lhs.map(\.y), rhs.map(\.x)))
        return zip(zip(x, y), z).map { xy, zValue in IntervalVector(x: xy.0, y: xy.1, z: zValue) }
    }

    private func elevated(_ values: [IntervalVector], to degree: Int) -> [IntervalVector] {
        var result = values
        while result.count - 1 < degree {
            let currentDegree = result.count - 1
            var next = [result[0]]
            for index in 1..<result.count {
                let alpha = Interval(Double(index) / Double(currentDegree + 1))
                next.append(add(scale(result[index - 1], by: alpha), scale(result[index], by: Interval(1) - alpha)))
            }
            next.append(result[result.count - 1])
            result = next
        }
        return result
    }

    private func elevated(_ values: [Interval], to degree: Int) -> [Interval] {
        var result = values
        while result.count - 1 < degree {
            let currentDegree = result.count - 1
            var next = [result[0]]
            for index in 1..<result.count {
                let alpha = Interval(Double(index) / Double(currentDegree + 1))
                next.append(result[index - 1] * alpha + result[index] * (Interval(1) - alpha))
            }
            next.append(result[result.count - 1])
            result = next
        }
        return result
    }

    private func productCoefficient(_ firstDegree: Int, _ firstIndex: Int, _ secondDegree: Int, _ secondIndex: Int) -> Interval {
        Interval(
            binomial(firstDegree, firstIndex) * binomial(secondDegree, secondIndex)
                / binomial(firstDegree + secondDegree, firstIndex + secondIndex)
        )
    }

    // MARK: - Linear algebra

    /// Minimises the energy rows' squares subject to the constraint rows (each `row · x + constant
    /// = 0` per coordinate): the constraints' solutions as a particular one plus their null space,
    /// read from a column-pivoted QR of the constraints' transpose, then the energy over that space.
    private func constrainedLeastSquares(constraints: [(row: [Double], constant: Vector3D)],
                                         energy: [(row: [Double], constant: Vector3D)], unknowns: Int) throws -> [Vector3D] {
        let count = constraints.count
        let transposeCount = try checkedMatrixElementCountForAdmission(unknowns, count)
        var transpose = Array(repeating: 0.0, count: transposeCount)
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
        let reducedCount = try checkedMatrixElementCountForAdmission(energy.count, freedom)
        var reduced = Array(repeating: 0.0, count: reducedCount)
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
