import Foundation
import CADCore
import CADGeometry

/// A surface that is a sum of products `f(u)·g(v)` divided by a product `W(u)·V(v)`, assembled as
/// one exact NURBS: every factor a polynomial spline on [0, 1], taken apart into Bézier pieces
/// between its breakpoints, multiplied piece by piece in the Bernstein basis, raised to one
/// degree per direction and joined with full-multiplicity interior knots. The weights are the
/// denominator's coefficients, positive because each factor's are.
///
/// A Boolean sum with rational sides is such a surface: its common denominator is the product of
/// the sides' weight functions, which separates into one of u and one of v.
package struct ExactRationalBooleanSum {
    /// A polynomial spline on [0, 1]: Bernstein coefficients of each piece between `breakpoints`,
    /// vectors (or scalars, in their x).
    package struct Pieces {
        package let breakpoints: [Double]
        package var pieces: [[Vector3D]]

        package var degree: Int { pieces.map { $0.count - 1 }.max() ?? 0 }
    }

    /// One product term: a vector factor times a scalar factor, in either order of directions.
    package struct Term {
        package let u: Pieces
        package let v: Pieces
        /// Whether `u` holds the vector and `v` the scalar (else the other way).
        package let vectorAlongU: Bool
    }

    private let tolerance: ModelingTolerance

    package init(tolerance: ModelingTolerance) {
        self.tolerance = tolerance
    }

    /// The pieces of a spline with `coefficients` on `knots` of `degree` (clamped, domain [0, 1]),
    /// between the spline's distinct knots.
    package func pieces(coefficients: [Vector3D], knots: [Double], degree: Int) throws -> Pieces {
        var curve = BSplineCurve3D(degree: degree, knots: knots, controlPoints: coefficients.map { .origin + $0 })
        var distinct: [Double] = []
        for knot in knots where distinct.last.map({ knot > $0 }) ?? true { distinct.append(knot) }
        guard distinct.first == 0, distinct.last == 1 else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                              message: "A Boolean sum's factor is a clamped spline on [0, 1].")
        }
        for knot in distinct.dropFirst().dropLast() {
            while curve.knots.filter({ $0 == knot }).count < degree {
                curve = try curve.insertingKnot(knot, tolerance: tolerance)
            }
        }
        let points = curve.controlPoints.map { $0 - Point3D.origin }
        return Pieces(breakpoints: distinct, pieces: (0..<(distinct.count - 1)).map { index in
            Array(points[(index * degree)...(index * degree + degree)])
        })
    }

    /// A polynomial on [0, 1] in Bernstein form restricted to each span between `breakpoints`.
    package func pieces(bezier: [Vector3D], breakpoints: [Double]) -> Pieces {
        let degree = bezier.count - 1
        return Pieces(breakpoints: breakpoints, pieces: zip(breakpoints, breakpoints.dropFirst()).map { lower, upper in
            (0...degree).map { j in
                blossom(bezier, Array(repeating: lower, count: degree - j) + Array(repeating: upper, count: j))
            }
        })
    }

    /// The product of two splines on the same breakpoints, one of them scalar (in its x).
    package func product(_ first: Pieces, scalar second: Pieces) throws -> Pieces {
        guard first.breakpoints == second.breakpoints else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                              message: "A Boolean sum multiplies factors on one set of breakpoints.")
        }
        return Pieces(breakpoints: first.breakpoints, pieces: zip(first.pieces, second.pieces).map { a, b in
            let (m, n) = (a.count - 1, b.count - 1)
            return (0...(m + n)).map { k in
                var sum = Vector3D.zero
                for i in max(0, k - n)...min(m, k) {
                    sum = sum + a[i] * (binomial(m, i) * binomial(n, k - i) / binomial(m + n, k) * b[k - i].x)
                }
                return sum
            }
        })
    }

    /// `first + second`, on the same breakpoints.
    package func sum(_ first: Pieces, _ second: Pieces) throws -> Pieces {
        guard first.breakpoints == second.breakpoints else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                              message: "A Boolean sum adds factors on one set of breakpoints.")
        }
        let degree = max(first.degree, second.degree)
        return Pieces(breakpoints: first.breakpoints, pieces: zip(first.pieces, second.pieces).map { a, b in
            zip(elevate(a, to: degree), elevate(b, to: degree)).map { $0 + $1 }
        })
    }

    /// `pieces` scaled by `factor`.
    package func scaled(_ pieces: Pieces, by factor: Double) -> Pieces {
        Pieces(breakpoints: pieces.breakpoints, pieces: pieces.pieces.map { $0.map { $0 * factor } })
    }

    /// The surface `Σ termᵢ / (denominatorU · denominatorV)`.
    package func surface(terms: [Term], denominatorU: Pieces, denominatorV: Pieces) throws -> BSplineSurface3D {
        let uDegree = max(denominatorU.degree, terms.map(\.u.degree).max() ?? 0, 1)
        let vDegree = max(denominatorV.degree, terms.map(\.v.degree).max() ?? 0, 1)
        func flattened(_ pieces: Pieces, degree: Int) -> [Vector3D] {
            var result: [Vector3D] = []
            for (index, piece) in pieces.pieces.enumerated() {
                let raised = elevate(piece, to: degree)
                result += index == 0 ? raised : Array(raised.dropFirst())
            }
            return result
        }
        func knots(_ breakpoints: [Double], degree: Int) -> [Double] {
            Array(repeating: 0, count: degree + 1) + breakpoints.dropFirst().dropLast().flatMap { Array(repeating: $0, count: degree) }
                + Array(repeating: 1, count: degree + 1)
        }
        let wu = flattened(denominatorU, degree: uDegree).map(\.x), wv = flattened(denominatorV, degree: vDegree).map(\.x)
        let flat = terms.map { (flattened($0.u, degree: uDegree), flattened($0.v, degree: vDegree), $0.vectorAlongU) }
        var points: [[Point3D]] = []
        var weights: [[Double]] = []
        for j in wv.indices {
            var row: [Point3D] = []
            var rowWeights: [Double] = []
            for i in wu.indices {
                let weight = wu[i] * wv[j]
                guard weight.isFinite, weight > 0 else {
                    throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                                      message: "A rational Boolean sum's weights must be positive.")
                }
                var numerator = Vector3D.zero
                for (u, v, vectorAlongU) in flat {
                    numerator = numerator + (vectorAlongU ? u[i] * v[j].x : v[j] * u[i].x)
                }
                let point = Point3D.origin + numerator * (1 / weight)
                try point.validate()
                row.append(point)
                rowWeights.append(weight)
            }
            points.append(row)
            weights.append(rowWeights)
        }
        return BSplineSurface3D(uDegree: uDegree, vDegree: vDegree,
                                uKnots: knots(denominatorU.breakpoints, degree: uDegree),
                                vKnots: knots(denominatorV.breakpoints, degree: vDegree),
                                controlPoints: points, weights: weights)
    }

    private func elevate(_ bezier: [Vector3D], to degree: Int) -> [Vector3D] {
        var values = bezier
        while values.count - 1 < degree {
            let n = values.count - 1
            values = (0...(n + 1)).map { i in
                let a = i > 0 ? values[i - 1] * (Double(i) / Double(n + 1)) : .zero
                let b = i <= n ? values[i] * (1 - Double(i) / Double(n + 1)) : .zero
                return a + b
            }
        }
        return values
    }

    private func blossom(_ bezier: [Vector3D], _ parameters: [Double]) -> Vector3D {
        var values = bezier
        for t in parameters {
            values = (0..<(values.count - 1)).map { values[$0] * (1 - t) + values[$0 + 1] * t }
        }
        return values[0]
    }

    private func binomial(_ n: Int, _ k: Int) -> Double {
        guard k >= 0, k <= n else { return 0 }
        var result = 1.0
        for i in 0..<min(k, n - k) { result = result * Double(n - i) / Double(i + 1) }
        return result
    }
}
