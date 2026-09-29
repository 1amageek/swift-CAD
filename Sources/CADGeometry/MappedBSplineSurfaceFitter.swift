import CADCore

/// A bicubic B-spline surface on a parameter rectangle through a smooth map of it, refined until
/// it stays within a deviation of the map: the surface a face takes when its support is carried
/// through a deformation, on the face's own parameters, so its trimming curves stay valid.
///
/// The surface is clamped with uniform knots and interpolates the map at the tensor grid of
/// Greville abscissae, solved one direction at a time. Its distance to the map is checked at the
/// quarter points of every knot cell, and while it exceeds the deviation one direction doubles its
/// spans, from one each: the one whose doubling brings the fit closer, so a map that bends one way
/// only is not split the other way. Each direction stops at `maximumSpanCount`
/// (`resourceLimitExceeded` when neither can double).
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
        var spans = (u: 1, v: 1)
        var result = try fit(uSpans: 1, vSpans: 1, u: u, v: v, tolerance: tolerance, point: point)
        while result.maximumDeviation > deviation {
            var candidates: [((u: Int, v: Int), Result)] = []
            if spans.u < maximumSpanCount {
                let next = (u: min(spans.u * 2, maximumSpanCount), v: spans.v)
                candidates.append((next, try fit(uSpans: next.u, vSpans: next.v, u: u, v: v, tolerance: tolerance, point: point)))
            }
            if spans.v < maximumSpanCount {
                let next = (u: spans.u, v: min(spans.v * 2, maximumSpanCount))
                candidates.append((next, try fit(uSpans: next.u, vSpans: next.v, u: u, v: v, tolerance: tolerance, point: point)))
            }
            guard let best = candidates.min(by: { $0.1.maximumDeviation < $1.1.maximumDeviation }) else {
                throw KernelError(phase: .geometry, code: .resourceLimitExceeded, residual: result.maximumDeviation, tolerance: tolerance,
                    message: "The mapped surface needs more than \(maximumSpanCount) spans each way to stay within \(deviation).")
            }
            (spans, result) = best
        }
        return result
    }

    private func fit(
        uSpans: Int,
        vSpans: Int,
        u: ScalarInterval,
        v: ScalarInterval,
        tolerance: ModelingTolerance,
        point: (Double, Double) throws -> Point3D
    ) throws -> Result {
        let p = Self.degree
        let knotsU = Self.clampedUniformKnots(spans: uSpans, on: u, degree: p)
        let knotsV = Self.clampedUniformKnots(spans: vSpans, on: v, degree: p)
        let uCount = uSpans + p, vCount = vSpans + p
        let grevilleU = Self.greville(knotsU, degree: p, count: uCount)
        let grevilleV = Self.greville(knotsV, degree: p, count: vCount)
        let solverU = try BandedCollocation(knots: knotsU, degree: p, abscissae: grevilleU)
        let solverV = try BandedCollocation(knots: knotsV, degree: p, abscissae: grevilleV)
        // samples[j][i] = map at (grevilleU[i], grevilleV[j]).
        let samples = try grevilleV.map { t in try grevilleU.map { s in try point(s, t) } }
        // Along u for each v row, then along v for each u column.
        let rows = try samples.map { try solverU.solve($0) }
        var controlPoints = Array(repeating: Array(repeating: Point3D.origin, count: uCount), count: vCount)
        for i in 0..<uCount {
            let column = try solverV.solve(rows.map { $0[i] })
            for j in 0..<vCount { controlPoints[j][i] = column[j] }
        }
        let surface = BSplineSurface3D(uDegree: p, vDegree: p, uKnots: knotsU, vKnots: knotsV, controlPoints: controlPoints)
        var maximum = 0.0
        let fractions = [0.0, 0.25, 0.5, 0.75]
        for cellV in 0..<vSpans {
            for cellU in 0..<uSpans {
                for a in fractions {
                    for b in fractions {
                        let s = u.lower + u.width * (Double(cellU) + a) / Double(uSpans)
                        let t = v.lower + v.width * (Double(cellV) + b) / Double(vSpans)
                        let distance = (try surface.point(u: s, v: t, tolerance: tolerance) - (try point(s, t))).length
                        maximum = max(maximum, distance)
                    }
                }
            }
        }
        // The far edges, which the cells' lower quarter points do not reach.
        for index in 0...(4 * vSpans) {
            let t = v.lower + v.width * Double(index) / Double(4 * vSpans)
            maximum = max(maximum, (try surface.point(u: u.upper, v: t, tolerance: tolerance) - (try point(u.upper, t))).length)
        }
        for index in 0...(4 * uSpans) {
            let s = u.lower + u.width * Double(index) / Double(4 * uSpans)
            maximum = max(maximum, (try surface.point(u: s, v: v.upper, tolerance: tolerance) - (try point(s, v.upper))).length)
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
