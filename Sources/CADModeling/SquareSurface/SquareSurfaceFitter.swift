import Foundation
import CADCore
import CADGeometry
import CADIR

/// Square's fit: the exact frame sheet refined into the space of the requested Degree and Spans,
/// its rows along hard sides kept, and every other control point minimizing the flatness-weighted
/// thin plate and membrane energy plus the Weight-scaled loose terms — a Free side's positions
/// and the boundary flow along sides without a face. A rational sheet keeps its refined weights
/// and is fitted in homogeneous coordinates.
package struct SquareSurfaceFitter {
    /// What a side of the frame asks of the sheet.
    package enum Constraint: Equatable {
        /// The sheet's rows 0…order along the side are the exact sheet's: position (0), tangent
        /// (1) or curvature (2) kept exactly.
        case hard(order: Int)
        /// Followed loosely: its positions weighted by the Weight.
        case loose
        /// Unconstrained (a completed side).
        case none
    }

    package struct Boundary {
        package var constraint: Constraint
        /// Whether the boundary flow applies along the side (a side without a face).
        package var flows: Bool

        package init(constraint: Constraint, flows: Bool) {
            self.constraint = constraint
            self.flows = flows
        }
    }

    /// The element budget of the least-squares matrix.
    package static let maximumElements = 12_000_000

    private let tolerance: ModelingTolerance

    package init(tolerance: ModelingTolerance) {
        self.tolerance = tolerance
    }

    /// The fitted sheet; `boundaries` in the order v = 0, u = 1, v = 1, u = 0 of `exact`.
    package func fit(exact: BSplineSurface3D, boundaries: [Boundary], options: SquareFitOptions,
                     featureID: FeatureID) throws -> BSplineSurface3D {
        try options.validate()
        guard boundaries.count == 4 else {
            throw failure(.invalidInput, "A Square's fit takes four boundaries.", featureID)
        }
        let space = try refined(normalized(exact, featureID: featureID), options: options)
        let nu = space.uControlPointCount, nv = space.vControlPointCount
        let count = nu * nv
        func index(_ i: Int, _ j: Int) -> Int { j * nu + i }

        // Hard rows: the exact sheet's control points along each hard side.
        var fixed = Array(repeating: false, count: count)
        for (side, boundary) in boundaries.enumerated() {
            guard case let .hard(order) = boundary.constraint else { continue }
            let across = side % 2 == 0 ? nv : nu
            guard order >= 0, order < across else {
                throw failure(.invalidInput, "A Square's side has fewer rows than its continuity needs.", featureID)
            }
            for depth in 0...order {
                for k in 0..<(side % 2 == 0 ? nu : nv) {
                    switch side {
                    case 0: fixed[index(k, depth)] = true
                    case 1: fixed[index(nu - 1 - depth, k)] = true
                    case 2: fixed[index(k, nv - 1 - depth)] = true
                    default: fixed[index(depth, k)] = true
                    }
                }
            }
        }
        let homogeneous: [[Double]] = (0..<count).map { k in
            let (i, j) = (k % nu, k / nu)
            let w = space.weights[j][i], p = space.controlPoints[j][i]
            return [p.x * w, p.y * w, p.z * w]
        }
        let free = (0..<count).filter { !fixed[$0] }
        guard free.isEmpty == false else { return space }
        var column = Array(repeating: -1, count: count)
        for (position, k) in free.enumerated() { column[k] = position }

        var rows = Rows()
        let uBasis = Basis(knots: space.uKnots, degree: space.uDegree, count: nu)
        let vBasis = Basis(knots: space.vKnots, degree: space.vDegree, count: nv)

        // Fairness over the unit square, exact for polynomial nets.
        let flatness = options.flatness
        for (u, wu) in try gaussPoints(knots: space.uKnots, count: space.uDegree + 1) {
            let bu = uBasis.derivatives(at: u, order: 2)
            for (v, wv) in try gaussPoints(knots: space.vKnots, count: space.vDegree + 1) {
                let bv = vBasis.derivatives(at: v, order: 2)
                let w = wu * wv
                var terms: [(Double, Int, Int)] = [((flatness * w).squareRoot(), 2, 0), ((2 * flatness * w).squareRoot(), 1, 1),
                                                    ((flatness * w).squareRoot(), 0, 2)]
                if flatness < 1 {
                    terms += [(((1 - flatness) * w).squareRoot(), 1, 0), (((1 - flatness) * w).squareRoot(), 0, 1)]
                }
                for (scale, du, dv) in terms {
                    rows.addScalar(product(bu, bv, du: du, dv: dv, nu: nu).map { ($0.0, $0.1 * scale) }, target: [0, 0, 0])
                }
            }
        }

        // Loose terms along each side, integrated along it.
        let weight = options.weight
        let meanNormal = options.boundaryFlow == .next
            ? try self.meanNormal(of: space, uBasis: uBasis, vBasis: vBasis, featureID: featureID) : nil
        for (side, boundary) in boundaries.enumerated() {
            let flow = boundary.flows ? options.boundaryFlow : .natural
            guard boundary.constraint == .loose || flow != .natural else { continue }
            let alongU = side % 2 == 0
            let fixedParameter: Double = (side == 0 || side == 3) ? 0 : 1
            for (t, wt) in try gaussPoints(knots: alongU ? space.uKnots : space.vKnots,
                                           count: (alongU ? space.uDegree : space.vDegree) + 1) {
                let scale = (weight * wt).squareRoot()
                let (u, v) = alongU ? (t, fixedParameter) : (fixedParameter, t)
                let bu = uBasis.derivatives(at: u, order: 1), bv = vBasis.derivatives(at: v, order: 1)
                let value = product(bu, bv, du: 0, dv: 0, nu: nu)
                let denominator = weightSum(value, space: space, nu: nu)
                let local = jet(space, u: u, v: v, uBasis: uBasis, vBasis: vBasis)
                let point = local.point - .origin
                if boundary.constraint == .loose {
                    rows.addScalar(value.map { ($0.0, $0.1 * scale / denominator) },
                                   target: [point.x * scale, point.y * scale, point.z * scale])
                }
                guard flow != .natural else { continue }
                // The cross derivative S_d = (A_d − S·W_d)/W, S the exact sheet's boundary point.
                let cross = alongU ? product(bu, bv, du: 0, dv: 1, nu: nu) : product(bu, bv, du: 1, dv: 0, nu: nu)
                let crossWeight = weightSum(cross, space: space, nu: nu)
                let offset = point * (crossWeight / denominator)
                let coefficients = cross.map { ($0.0, $0.1 * scale / denominator) }
                switch flow {
                case .natural:
                    break
                case .adjacent:
                    // The neighbouring sides' derivatives at the side's corners, blended along it.
                    let first = alongU ? jet(space, u: 0, v: v, uBasis: uBasis, vBasis: vBasis).v
                        : jet(space, u: u, v: 0, uBasis: uBasis, vBasis: vBasis).u
                    let last = alongU ? jet(space, u: 1, v: v, uBasis: uBasis, vBasis: vBasis).v
                        : jet(space, u: u, v: 1, uBasis: uBasis, vBasis: vBasis).u
                    let target = first * (1 - t) + last * t + offset
                    rows.addScalar(coefficients, target: [target.x * scale, target.y * scale, target.z * scale])
                case .normal, .next:
                    let tangent = try (alongU ? local.u : local.v).normalized(tolerance: tolerance.distance)
                    var directions = [tangent]
                    if let meanNormal { directions.append(meanNormal) }
                    for direction in directions {
                        let components = [direction.x, direction.y, direction.z]
                        rows.addCoupled((0..<3).flatMap { c in coefficients.map { (c, $0.0, $0.1 * components[c]) } },
                                        target: offset.dot(direction) * scale)
                    }
                }
            }
        }

        let solution = try rows.solve(free: free, column: column, fixedValues: homogeneous, featureID: featureID, failure: failure)
        var points = space.controlPoints
        for (position, k) in free.enumerated() {
            let (i, j) = (k % nu, k / nu)
            let w = space.weights[j][i]
            points[j][i] = Point3D(x: solution[position][0] / w, y: solution[position][1] / w, z: solution[position][2] / w)
        }
        let surface = BSplineSurface3D(uDegree: space.uDegree, vDegree: space.vDegree, uKnots: space.uKnots, vKnots: space.vKnots,
                                       controlPoints: points, weights: space.weights)
        try surface.validate(tolerance: tolerance)
        return surface
    }

    // MARK: - Space

    private func normalized(_ surface: BSplineSurface3D, featureID: FeatureID) throws -> BSplineSurface3D {
        guard let u0 = surface.uKnots.first, let u1 = surface.uKnots.last, u1 > u0,
              let v0 = surface.vKnots.first, let v1 = surface.vKnots.last, v1 > v0 else {
            throw failure(.invalidInput, "A Square's exact sheet has a degenerate knot vector.", featureID)
        }
        return BSplineSurface3D(uDegree: surface.uDegree, vDegree: surface.vDegree,
                                uKnots: surface.uKnots.map { ($0 - u0) / (u1 - u0) }, vKnots: surface.vKnots.map { ($0 - v0) / (v1 - v0) },
                                controlPoints: surface.controlPoints, weights: surface.weights)
    }

    /// `surface` raised to at least the requested degrees, with the requested spans' uniform knots.
    private func refined(_ surface: BSplineSurface3D, options: SquareFitOptions) throws -> BSplineSurface3D {
        var space = surface
        while space.uDegree < options.uDegree { space = try space.elevatingDegree(direction: .u, tolerance: tolerance) }
        while space.vDegree < options.vDegree { space = try space.elevatingDegree(direction: .v, tolerance: tolerance) }
        for (direction, spans) in [(SurfaceParameterDirection.u, options.uSpans), (.v, options.vSpans)] {
            for k in 1..<max(spans, 1) {
                let value = Double(k) / Double(spans)
                let knots = direction == .u ? space.uKnots : space.vKnots
                if knots.contains(where: { abs($0 - value) <= 1e-12 }) { continue }
                space = try space.insertingKnot(direction: direction, value: value, tolerance: tolerance)
            }
        }
        return space
    }

    private func meanNormal(of surface: BSplineSurface3D, uBasis: Basis, vBasis: Basis, featureID: FeatureID) throws -> Vector3D {
        var sum = Vector3D.zero
        for a in 0...4 {
            for b in 0...4 {
                let local = jet(surface, u: Double(a) / 4, v: Double(b) / 4, uBasis: uBasis, vBasis: vBasis)
                let normal = local.u.cross(local.v)
                if normal.length > 0 { sum = sum + normal * (1 / normal.length) }
            }
        }
        guard sum.length > 1e-9 else {
            throw failure(.invalidInput, "A Square's Next flow needs a frame with a mean plane.", featureID)
        }
        return sum * (1 / sum.length)
    }

    private func weightSum(_ terms: [(Int, Double)], space: BSplineSurface3D, nu: Int) -> Double {
        terms.reduce(0.0) { $0 + $1.1 * space.weights[$1.0 / nu][$1.0 % nu] }
    }

    /// The tensor products of the u and v basis derivatives of the given orders, by control index.
    private func product(_ bu: Basis.Values, _ bv: Basis.Values, du: Int, dv: Int, nu: Int) -> [(Int, Double)] {
        var result: [(Int, Double)] = []
        for (i, nu0) in bu.derivatives[du].enumerated() where nu0 != 0 {
            for (j, nv0) in bv.derivatives[dv].enumerated() where nv0 != 0 {
                result.append((j * nu + i, nu0 * nv0))
            }
        }
        return result
    }

    /// The sheet's point and first derivatives at (u, v), from its rational net.
    private func jet(_ surface: BSplineSurface3D, u: Double, v: Double, uBasis: Basis, vBasis: Basis)
        -> (point: Point3D, u: Vector3D, v: Vector3D) {
        let nu = surface.uControlPointCount
        let bu = uBasis.derivatives(at: u, order: 1), bv = vBasis.derivatives(at: v, order: 1)
        func sum(_ du: Int, _ dv: Int) -> (Vector3D, Double) {
            var a = Vector3D.zero, w = 0.0
            for (k, value) in product(bu, bv, du: du, dv: dv, nu: nu) {
                let weight = surface.weights[k / nu][k % nu]
                a = a + (surface.controlPoints[k / nu][k % nu] - .origin) * (value * weight)
                w += value * weight
            }
            return (a, w)
        }
        let (a, w) = sum(0, 0), (au, wu) = sum(1, 0), (av, wv) = sum(0, 1)
        let point = a * (1 / w)
        return (.origin + point, (au - point * wu) * (1 / w), (av - point * wv) * (1 / w))
    }

    /// Gauss–Legendre points and weights, `count` per nonempty knot span.
    private func gaussPoints(knots: [Double], count: Int) throws -> [(Double, Double)] {
        let (nodes, weights) = try Self.legendre(count)
        var result: [(Double, Double)] = []
        for (a, b) in zip(knots, knots.dropFirst()) where b > a {
            let half = (b - a) / 2, middle = (a + b) / 2
            for k in nodes.indices { result.append((middle + half * nodes[k], half * weights[k])) }
        }
        return result
    }

    private static func legendre(_ n: Int) throws -> ([Double], [Double]) {
        var nodes: [Double] = [], weights: [Double] = []
        for k in 1...n {
            var x = cos(Double.pi * (Double(k) - 0.25) / (Double(n) + 0.5))
            var derivative = 0.0
            for _ in 0..<100 {
                var p0 = 1.0, p1 = x
                for m in stride(from: 2, through: n, by: 1) {
                    let p2 = ((2 * Double(m) - 1) * x * p1 - (Double(m) - 1) * p0) / Double(m)
                    p0 = p1
                    p1 = p2
                }
                // p1 = P_n(x), p0 = P_{n−1}(x).
                derivative = Double(n) * (x * p1 - p0) / (x * x - 1)
                let step = p1 / derivative
                x -= step
                if abs(step) < 1e-15 { break }
            }
            nodes.append(x)
            weights.append(2 / ((1 - x * x) * derivative * derivative))
        }
        guard nodes.allSatisfy(\.isFinite), weights.allSatisfy(\.isFinite) else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: nil, message: "Gauss–Legendre nodes did not converge.")
        }
        return (nodes, weights)
    }

    private func failure(_ code: KernelErrorCode, _ message: String, _ featureID: FeatureID) -> KernelError {
        KernelError(phase: .evaluation, code: code, featureID: featureID, tolerance: tolerance, message: message)
    }

    // MARK: - Basis

    /// A clamped B-spline basis's values and derivatives at a parameter, over all its functions.
    private struct Basis {
        struct Values {
            /// derivatives[k][i]: the k-th derivative of basis function i.
            let derivatives: [[Double]]
        }

        let knots: [Double]
        let degree: Int
        let count: Int

        func derivatives(at x: Double, order: Int) -> Values {
            let clamped = BSplineBasis.clampedParameter(x, knots: knots, degree: degree)
            return Values(derivatives: (0...order).map {
                BSplineBasis.derivativeValues(parameter: clamped, degree: degree, derivativeOrder: $0, knots: knots, count: count)
            })
        }
    }

    // MARK: - Least squares

    /// The fit's rows: scalar rows shared by the three coordinates (each with its own target) and
    /// coupled rows over all three.
    private struct Rows {
        var scalar: [(terms: [(Int, Double)], target: [Double])] = []
        var coupled: [(terms: [(Int, Int, Double)], target: Double)] = []

        mutating func addScalar(_ terms: [(Int, Double)], target: [Double]) {
            scalar.append((terms, target))
        }

        mutating func addCoupled(_ terms: [(Int, Int, Double)], target: Double) {
            coupled.append((terms, target))
        }

        func solve(free: [Int], column: [Int], fixedValues: [[Double]], featureID: FeatureID,
                   failure: (KernelErrorCode, String, FeatureID) -> KernelError) throws -> [[Double]] {
            let unknowns = free.count
            if coupled.isEmpty {
                let elements = scalar.count.multipliedReportingOverflow(by: unknowns)
                guard !elements.overflow, elements.partialValue <= SquareSurfaceFitter.maximumElements else {
                    throw failure(.resourceLimitExceeded, "A Square's fit exceeds its matrix budget; lower its degree or spans.", featureID)
                }
                var matrix = Array(repeating: 0.0, count: scalar.count * unknowns)
                var targets = Array(repeating: Array(repeating: 0.0, count: scalar.count), count: 3)
                for (row, entry) in scalar.enumerated() {
                    var target = entry.target
                    for (k, value) in entry.terms {
                        if column[k] >= 0 {
                            matrix[row * unknowns + column[k]] += value
                        } else {
                            for c in 0..<3 { target[c] -= value * fixedValues[k][c] }
                        }
                    }
                    for c in 0..<3 { targets[c][row] = target[c] }
                }
                let solved = try solveLeastSquares(matrix, targets: targets, columns: unknowns, featureID: featureID, failure: failure)
                return (0..<unknowns).map { k in [solved[0][k], solved[1][k], solved[2][k]] }
            }
            let columns = 3 * unknowns
            let rowCount = 3 * scalar.count + coupled.count
            let elements = rowCount.multipliedReportingOverflow(by: columns)
            guard !elements.overflow, elements.partialValue <= SquareSurfaceFitter.maximumElements else {
                throw failure(.resourceLimitExceeded, "A Square's fit exceeds its matrix budget; lower its degree or spans.", featureID)
            }
            var matrix = Array(repeating: 0.0, count: rowCount * columns)
            var target = Array(repeating: 0.0, count: rowCount)
            var row = 0
            for entry in scalar {
                for c in 0..<3 {
                    var value = entry.target[c]
                    for (k, coefficient) in entry.terms {
                        if column[k] >= 0 {
                            matrix[row * columns + c * unknowns + column[k]] += coefficient
                        } else {
                            value -= coefficient * fixedValues[k][c]
                        }
                    }
                    target[row] = value
                    row += 1
                }
            }
            for entry in coupled {
                var value = entry.target
                for (c, k, coefficient) in entry.terms {
                    if column[k] >= 0 {
                        matrix[row * columns + c * unknowns + column[k]] += coefficient
                    } else {
                        value -= coefficient * fixedValues[k][c]
                    }
                }
                target[row] = value
                row += 1
            }
            let solved = try solveLeastSquares(matrix, targets: [target], columns: columns, featureID: featureID, failure: failure)[0]
            return (0..<unknowns).map { k in [solved[k], solved[unknowns + k], solved[2 * unknowns + k]] }
        }

        private func solveLeastSquares(_ matrix: [Double], targets: [[Double]], columns: Int, featureID: FeatureID,
                                       failure: (KernelErrorCode, String, FeatureID) -> KernelError) throws -> [[Double]] {
            do {
                return try SurfaceFittingLeastSquares.solve(
                    objective: matrix, targets: targets, constraints: [], values: targets.map { _ in [] }, columns: columns,
                    relativeRankTolerance: 1e-11, constraintTolerance: 0, maximumElements: SquareSurfaceFitter.maximumElements * 2
                )
            } catch let error as KernelError where error.code == .singularSystem {
                throw failure(.singularSystem, "A Square's frame does not determine its sheet (\(error.message)).", featureID)
            }
        }
    }
}
