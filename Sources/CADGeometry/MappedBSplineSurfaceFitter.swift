import CADCore

/// A bicubic B-spline surface on a parameter rectangle through a smooth map of it, refined until
/// it stays within a deviation of the map: the surface a face takes when its support is carried
/// through a deformation, on the face's own parameters, so its trimming curves stay valid.
///
/// The surface is clamped with uniform knots and interpolates the map at the tensor grid of
/// Greville abscissae, solved one direction at a time. Its distance to the map is checked at the
/// quarter points of every knot cell, and while it exceeds the deviation both directions double
/// their spans from one, up to `maximumSpanCount` each (`resourceLimitExceeded` beyond).
package struct MappedBSplineSurfaceFitter: Sendable {
    package struct Result: Sendable {
        package var surface: BSplineSurface3D
        /// The largest distance found at the check points between the surface and the map.
        package var maximumDeviation: Double
    }

    package static let degree = 3

    package let deviation: Double
    package let maximumSpanCount: Int

    package init(deviation: Double, maximumSpanCount: Int = 128) throws {
        guard deviation.isFinite, deviation > 0, maximumSpanCount >= 1 else {
            throw KernelError(phase: .validation, code: .invalidInput, tolerance: nil,
                message: "A surface fit needs a positive deviation and span budget.")
        }
        self.deviation = deviation
        self.maximumSpanCount = maximumSpanCount
    }

    package func fit(
        u: ScalarInterval,
        v: ScalarInterval,
        tolerance: ModelingTolerance,
        point: (Double, Double) throws -> Point3D
    ) throws -> Result {
        guard u.width > 0, v.width > 0, u.lower.isFinite, u.upper.isFinite, v.lower.isFinite, v.upper.isFinite else {
            throw KernelError(phase: .validation, code: .invalidInput, tolerance: tolerance,
                message: "A surface fit needs a finite parameter rectangle of positive extent.")
        }
        // One span first: a map that is affine over the rectangle is fitted exactly by it.
        var spans = 1
        while true {
            let result = try fit(spans: min(spans, maximumSpanCount), u: u, v: v, tolerance: tolerance, point: point)
            if result.maximumDeviation <= deviation { return result }
            guard spans < maximumSpanCount else {
                throw KernelError(phase: .geometry, code: .resourceLimitExceeded, residual: result.maximumDeviation, tolerance: tolerance,
                    message: "The mapped surface needs more than \(maximumSpanCount) spans each way to stay within \(deviation).")
            }
            spans *= 2
        }
    }

    private func fit(
        spans: Int,
        u: ScalarInterval,
        v: ScalarInterval,
        tolerance: ModelingTolerance,
        point: (Double, Double) throws -> Point3D
    ) throws -> Result {
        let p = Self.degree
        let knotsU = Self.clampedUniformKnots(spans: spans, on: u, degree: p)
        let knotsV = Self.clampedUniformKnots(spans: spans, on: v, degree: p)
        let count = spans + p
        let grevilleU = Self.greville(knotsU, degree: p, count: count)
        let grevilleV = Self.greville(knotsV, degree: p, count: count)
        let solverU = try BandedCollocation(knots: knotsU, degree: p, abscissae: grevilleU)
        let solverV = try BandedCollocation(knots: knotsV, degree: p, abscissae: grevilleV)
        // samples[j][i] = map at (grevilleU[i], grevilleV[j]).
        let samples = try grevilleV.map { t in try grevilleU.map { s in try point(s, t) } }
        // Along u for each v row, then along v for each u column.
        let rows = try samples.map { try solverU.solve($0) }
        var controlPoints = Array(repeating: Array(repeating: Point3D.origin, count: count), count: count)
        for i in 0..<count {
            let column = try solverV.solve(rows.map { $0[i] })
            for j in 0..<count { controlPoints[j][i] = column[j] }
        }
        let surface = BSplineSurface3D(uDegree: p, vDegree: p, uKnots: knotsU, vKnots: knotsV, controlPoints: controlPoints)
        var maximum = 0.0
        let fractions = [0.0, 0.25, 0.5, 0.75]
        for cellV in 0..<spans {
            for cellU in 0..<spans {
                for a in fractions {
                    for b in fractions {
                        let s = u.lower + u.width * (Double(cellU) + a) / Double(spans)
                        let t = v.lower + v.width * (Double(cellV) + b) / Double(spans)
                        let distance = (try surface.point(u: s, v: t, tolerance: tolerance) - (try point(s, t))).length
                        maximum = max(maximum, distance)
                    }
                }
            }
        }
        // The far edges, which the cells' lower quarter points do not reach.
        for index in 0...(4 * spans) {
            let fraction = Double(index) / Double(4 * spans)
            for (s, t) in [(u.upper, v.lower + v.width * fraction), (u.lower + u.width * fraction, v.upper)] {
                maximum = max(maximum, (try surface.point(u: s, v: t, tolerance: tolerance) - (try point(s, t))).length)
            }
        }
        return Result(surface: surface, maximumDeviation: maximum)
    }

    private static func clampedUniformKnots(spans: Int, on interval: ScalarInterval, degree: Int) -> [Double] {
        Array(repeating: interval.lower, count: degree + 1)
            + (1..<max(spans, 1)).map { interval.lower + interval.width * Double($0) / Double(spans) }
            + Array(repeating: interval.upper, count: degree + 1)
    }

    private static func greville(_ knots: [Double], degree: Int, count: Int) -> [Double] {
        (0..<count).map { index in
            knots[(index + 1)...(index + degree)].reduce(0, +) / Double(degree)
        }
    }
}

/// Interpolation of values at abscissae by a B-spline of the given knots: the collocation matrix
/// factored once (Gaussian elimination, which a B-spline collocation matrix at Greville abscissae
/// admits without pivoting), then solved for each set of values.
private struct BandedCollocation {
    private var lower: [[Double]]
    private var upper: [[Double]]
    private let count: Int

    init(knots: [Double], degree: Int, abscissae: [Double]) throws {
        count = abscissae.count
        var matrix = Array(repeating: Array(repeating: 0.0, count: count), count: count)
        for (row, parameter) in abscissae.enumerated() {
            let basis = BSplineBasis.nonzeroValues(parameter: parameter, degree: degree, knots: knots, count: count)
            for (offset, value) in basis.values.enumerated() where basis.startIndex + offset < count {
                matrix[row][basis.startIndex + offset] = value
            }
        }
        lower = Array(repeating: Array(repeating: 0.0, count: count), count: count)
        upper = matrix
        for pivot in 0..<count {
            guard abs(upper[pivot][pivot]) > 1e-14 else {
                throw KernelError(phase: .geometry, code: .singularGeometry, tolerance: nil,
                    message: "A surface fit's collocation matrix is singular.")
            }
            lower[pivot][pivot] = 1
            for row in (pivot + 1)..<count where upper[row][pivot] != 0 {
                let factor = upper[row][pivot] / upper[pivot][pivot]
                lower[row][pivot] = factor
                for column in pivot..<count { upper[row][column] -= factor * upper[pivot][column] }
            }
        }
    }

    func solve(_ values: [Point3D]) throws -> [Point3D] {
        var forward = values.map { Vector3D(x: $0.x, y: $0.y, z: $0.z) }
        for row in 0..<count {
            for column in 0..<row where lower[row][column] != 0 {
                forward[row] = forward[row] - forward[column] * lower[row][column]
            }
        }
        var solution = forward
        for row in stride(from: count - 1, through: 0, by: -1) {
            var value = forward[row]
            for column in (row + 1)..<count where upper[row][column] != 0 {
                value = value - solution[column] * upper[row][column]
            }
            solution[row] = value * (1 / upper[row][row])
        }
        return solution.map { Point3D(x: $0.x, y: $0.y, z: $0.z) }
    }
}
