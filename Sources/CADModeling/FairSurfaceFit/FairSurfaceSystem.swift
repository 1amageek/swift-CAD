import Foundation
import CADCore
import CADGeometry

/// The least-squares system of a fair tensor B-spline fit, shared by Square and XNURBS: rows over
/// its (homogeneous) control points, each a linear combination of basis products — scalar rows
/// shared by the three coordinates with a target each, and coupled rows over all three — solved
/// for the free control points with the fixed ones moved to the targets: scalar rows by the
/// normal equations accumulated sparsely and a Cholesky factor, coupled ones by column-pivoted QR.
/// A rank-deficient system is a typed failure, never an arbitrary minimum.
package struct FairSurfaceSystem {
    /// A clamped B-spline basis's values and derivatives at a parameter, over all its functions.
    package struct Basis {
        package let knots: [Double]
        package let degree: Int
        package let count: Int

        package init(knots: [Double], degree: Int, count: Int) {
            self.knots = knots
            self.degree = degree
            self.count = count
        }

        /// derivatives[k][i]: the k-th derivative of basis function i at `x`.
        package func derivatives(at x: Double, order: Int) -> [[Double]] {
            let clamped = BSplineBasis.clampedParameter(x, knots: knots, degree: degree)
            return (0...order).map {
                BSplineBasis.derivativeValues(parameter: clamped, degree: degree, derivativeOrder: $0, knots: knots, count: count)
            }
        }
    }

    /// The element budget of the least-squares matrix.
    package static let maximumElements = 12_000_000

    package private(set) var scalar: [(terms: [(Int, Double)], target: [Double])] = []
    package private(set) var coupled: [(terms: [(Int, Int, Double)], target: Double)] = []

    package init() {}

    package mutating func addScalar(_ terms: [(Int, Double)], target: [Double]) {
        scalar.append((terms, target))
    }

    package mutating func addCoupled(_ terms: [(Int, Int, Double)], target: Double) {
        coupled.append((terms, target))
    }

    /// The fairness rows over the unit square: `flatness`·(|S_uu|² + 2|S_uv|² + |S_vv|²) plus
    /// (1 − flatness)·(|S_u|² + |S_v|²), Gauss–Legendre with degree + 1 points per span, exact for
    /// polynomial nets.
    package mutating func addFairness(uBasis: Basis, vBasis: Basis, flatness: Double) throws {
        let nu = uBasis.count
        for (u, wu) in try Self.gaussPoints(knots: uBasis.knots, count: uBasis.degree + 1) {
            let bu = uBasis.derivatives(at: u, order: 2)
            for (v, wv) in try Self.gaussPoints(knots: vBasis.knots, count: vBasis.degree + 1) {
                let bv = vBasis.derivatives(at: v, order: 2)
                let w = wu * wv
                var terms: [(Double, Int, Int)] = [((flatness * w).squareRoot(), 2, 0), ((2 * flatness * w).squareRoot(), 1, 1),
                                                    ((flatness * w).squareRoot(), 0, 2)]
                if flatness < 1 {
                    terms += [(((1 - flatness) * w).squareRoot(), 1, 0), (((1 - flatness) * w).squareRoot(), 0, 1)]
                }
                for (scale, du, dv) in terms {
                    addScalar(Self.product(bu, bv, du: du, dv: dv, nu: nu).map { ($0.0, $0.1 * scale) }, target: [0, 0, 0])
                }
            }
        }
    }

    /// The tensor products of the u and v basis derivatives of the given orders, by control index
    /// j·nu + i.
    package static func product(_ bu: [[Double]], _ bv: [[Double]], du: Int, dv: Int, nu: Int) -> [(Int, Double)] {
        var result: [(Int, Double)] = []
        for (i, nu0) in bu[du].enumerated() where nu0 != 0 {
            for (j, nv0) in bv[dv].enumerated() where nv0 != 0 {
                result.append((j * nu + i, nu0 * nv0))
            }
        }
        return result
    }

    /// Gauss–Legendre points and weights, `count` per nonempty knot span.
    package static func gaussPoints(knots: [Double], count: Int) throws -> [(Double, Double)] {
        let (nodes, weights) = try legendre(count)
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

    /// The free control points (in `free`'s order, three coordinates each), the fixed ones'
    /// `fixedValues` moved to the targets; `column[k]` is control point k's free position or −1.
    package func solve(free: [Int], column: [Int], fixedValues: [[Double]], featureID: FeatureID,
                       failure: (KernelErrorCode, String, FeatureID) -> KernelError) throws -> [[Double]] {
        let unknowns = free.count
        if coupled.isEmpty {
            // The normal equations, accumulated from the sparse rows: AᵀA over the free points and
            // Aᵀb for each coordinate, then a Cholesky factor — each row touches only the few
            // control points its basis products reach, so this costs far less than a dense QR.
            let elements = unknowns.multipliedReportingOverflow(by: unknowns)
            guard !elements.overflow, elements.partialValue <= Self.maximumElements else {
                throw failure(.resourceLimitExceeded, "The fit exceeds its matrix budget; lower its degree or spans.", featureID)
            }
            var normal = Array(repeating: 0.0, count: unknowns * unknowns)
            var right = Array(repeating: Array(repeating: 0.0, count: unknowns), count: 3)
            for entry in scalar {
                var target = entry.target
                var local: [(Int, Double)] = []
                local.reserveCapacity(entry.terms.count)
                for (k, value) in entry.terms {
                    if column[k] >= 0 {
                        local.append((column[k], value))
                    } else {
                        for c in 0..<3 { target[c] -= value * fixedValues[k][c] }
                    }
                }
                for (a, va) in local {
                    for c in 0..<3 { right[c][a] += va * target[c] }
                    for (b, vb) in local where b <= a { normal[a * unknowns + b] += va * vb }
                }
            }
            let solved = try Self.choleskySolve(normal, right: right, count: unknowns, featureID: featureID, failure: failure)
            return (0..<unknowns).map { k in [solved[0][k], solved[1][k], solved[2][k]] }
        }
        let columns = 3 * unknowns
        let rowCount = 3 * scalar.count + coupled.count
        let elements = rowCount.multipliedReportingOverflow(by: columns)
        guard !elements.overflow, elements.partialValue <= Self.maximumElements else {
            throw failure(.resourceLimitExceeded, "The fit exceeds its matrix budget; lower its degree or spans.", featureID)
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

    /// Solves the symmetric positive definite system whose lower triangle is `matrix` (row-major)
    /// for each right-hand side; a pivot below 10⁻¹² of the largest diagonal entry means the rows
    /// leave a direction undetermined, a typed failure.
    private static func choleskySolve(_ matrix: [Double], right: [[Double]], count n: Int, featureID: FeatureID,
                                      failure: (KernelErrorCode, String, FeatureID) -> KernelError) throws -> [[Double]] {
        var l = matrix
        let largest = (0..<n).map { l[$0 * n + $0] }.max() ?? 0
        guard largest > 0, largest.isFinite else {
            throw failure(.singularSystem, "The frame does not determine its sheet.", featureID)
        }
        for j in 0..<n {
            var diagonal = l[j * n + j]
            for k in 0..<j { diagonal -= l[j * n + k] * l[j * n + k] }
            guard diagonal > largest * 1e-12 else {
                throw failure(.singularSystem, "The frame does not determine its sheet (a direction of the net is unconstrained).", featureID)
            }
            let pivot = diagonal.squareRoot()
            l[j * n + j] = pivot
            for i in (j + 1)..<max(n, j + 1) {
                var value = l[i * n + j]
                for k in 0..<j { value -= l[i * n + k] * l[j * n + k] }
                l[i * n + j] = value / pivot
            }
        }
        return try right.map { b in
            var y = b
            for i in 0..<n {
                var value = y[i]
                for k in 0..<i { value -= l[i * n + k] * y[k] }
                y[i] = value / l[i * n + i]
            }
            for i in stride(from: n - 1, through: 0, by: -1) {
                var value = y[i]
                for k in (i + 1)..<max(n, i + 1) { value -= l[k * n + i] * y[k] }
                y[i] = value / l[i * n + i]
            }
            guard y.allSatisfy(\.isFinite) else {
                throw failure(.singularSystem, "The fit's solution is not finite.", featureID)
            }
            return y
        }
    }

    private func solveLeastSquares(_ matrix: [Double], targets: [[Double]], columns: Int, featureID: FeatureID,
                                   failure: (KernelErrorCode, String, FeatureID) -> KernelError) throws -> [[Double]] {
        do {
            return try SurfaceFittingLeastSquares.solve(
                objective: matrix, targets: targets, constraints: [], values: targets.map { _ in [] }, columns: columns,
                relativeRankTolerance: 1e-11, constraintTolerance: 0, maximumElements: Self.maximumElements * 2
            )
        } catch let error as KernelError where error.code == .singularSystem {
            throw failure(.singularSystem, "The frame does not determine its sheet (\(error.message)).", featureID)
        }
    }
}
