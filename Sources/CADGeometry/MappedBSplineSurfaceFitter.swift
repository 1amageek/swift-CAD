import CADCore

/// A B-spline surface on a parameter rectangle through a smooth map of it, bicubic unless other
/// degrees are asked for, refined until it stays within a deviation of the map: the surface a face
/// takes when its support is carried through a deformation, or rebuilt, on the face's own
/// parameters, so its trimming curves stay valid.
///
/// The surface is clamped with uniform knots and interpolates the map at the tensor grid of
/// Greville abscissae, solved one direction at a time. Its distance to the map is checked at the
/// quarter points of every knot cell, and while it exceeds the deviation the spans double, from
/// one each: in the direction whose doubling brings the fit closest by a tenth or more, so a map
/// that bends one way only is not split the other way, and in both when neither does (a first
/// split can stray further before the next close in). Each direction stops at `maximumSpanCount`
/// (`resourceLimitExceeded` when neither can double). `fit(layout:u:v:tolerance:point:)` fits one
/// given layout of degrees and spans and reports how far it strays.
package struct MappedBSplineSurfaceFitter: Sendable {
    package struct Result: Sendable {
        package var surface: BSplineSurface3D
        /// The largest distance found at the check points between the surface and the map.
        package var maximumDeviation: Double
    }

    /// The degrees and span counts of a fitted surface along U and V.
    package struct Layout: Hashable, Sendable {
        package var uDegree: Int
        package var vDegree: Int
        package var uSpans: Int
        package var vSpans: Int

        package init(uDegree: Int, vDegree: Int, uSpans: Int, vSpans: Int) {
            self.uDegree = uDegree
            self.vDegree = vDegree
            self.uSpans = uSpans
            self.vSpans = vSpans
        }
    }

    package let deviation: Double
    package let maximumSpanCount: Int
    package let uDegree: Int
    package let vDegree: Int

    package init(deviation: Double, maximumSpanCount: Int = 128, uDegree: Int = 3, vDegree: Int = 3) throws {
        guard deviation.isFinite, deviation > 0, maximumSpanCount >= 1, uDegree >= 1, vDegree >= 1 else {
            throw KernelError(phase: .validation, code: .invalidInput, tolerance: nil,
                message: "A surface fit needs a positive deviation, span budget and degrees.")
        }
        self.deviation = deviation
        self.maximumSpanCount = maximumSpanCount
        self.uDegree = uDegree
        self.vDegree = vDegree
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
        var result = try Self.fit(layout: layout(1, 1), u: u, v: v, tolerance: tolerance, point: point)
        while result.maximumDeviation > deviation {
            var candidates: [((u: Int, v: Int), Result)] = []
            if spans.u < maximumSpanCount {
                let next = (u: min(spans.u * 2, maximumSpanCount), v: spans.v)
                candidates.append((next, try Self.fit(layout: layout(next.u, next.v), u: u, v: v, tolerance: tolerance, point: point)))
            }
            if spans.v < maximumSpanCount {
                let next = (u: spans.u, v: min(spans.v * 2, maximumSpanCount))
                candidates.append((next, try Self.fit(layout: layout(next.u, next.v), u: u, v: v, tolerance: tolerance, point: point)))
            }
            guard candidates.isEmpty == false else {
                throw KernelError(phase: .geometry, code: .resourceLimitExceeded, residual: result.maximumDeviation, tolerance: tolerance,
                    message: "The mapped surface needs more than \(maximumSpanCount) spans each way to stay within \(deviation).")
            }
            // A doubling that brings the fit closer wins; when neither does (a first split can
            // stray further before the next ones close in), both directions double.
            let improving = candidates.filter { $0.1.maximumDeviation < result.maximumDeviation * 0.9 }
            if let best = improving.min(by: { $0.1.maximumDeviation < $1.1.maximumDeviation }) {
                (spans, result) = best
            } else {
                spans = (u: min(spans.u * 2, maximumSpanCount), v: min(spans.v * 2, maximumSpanCount))
                result = try Self.fit(layout: layout(spans.u, spans.v), u: u, v: v, tolerance: tolerance, point: point)
            }
        }
        return result
    }

    private func layout(_ uSpans: Int, _ vSpans: Int) -> Layout {
        Layout(uDegree: uDegree, vDegree: vDegree, uSpans: uSpans, vSpans: vSpans)
    }

    /// The surface of `layout` through `point` at its Greville grid, and its largest distance from
    /// `point` at the quarter points of every knot cell and along the far sides.
    package static func fit(
        layout: Layout,
        u: ScalarInterval,
        v: ScalarInterval,
        tolerance: ModelingTolerance,
        point: (Double, Double) throws -> Point3D
    ) throws -> Result {
        guard layout.uDegree >= 1, layout.vDegree >= 1, layout.uSpans >= 1, layout.vSpans >= 1 else {
            throw KernelError(phase: .validation, code: .invalidInput, tolerance: tolerance,
                message: "A surface fit's layout needs degrees and spans of at least one.")
        }
        guard u.width > 0, v.width > 0, u.lower.isFinite, u.upper.isFinite, v.lower.isFinite, v.upper.isFinite else {
            throw KernelError(phase: .validation, code: .invalidInput, tolerance: tolerance,
                message: "A surface fit needs a finite parameter rectangle of positive extent.")
        }
        let (uSpans, vSpans) = (layout.uSpans, layout.vSpans)
        let knotsU = clampedUniformKnots(spans: uSpans, on: u, degree: layout.uDegree)
        let knotsV = clampedUniformKnots(spans: vSpans, on: v, degree: layout.vDegree)
        let uCount = uSpans + layout.uDegree, vCount = vSpans + layout.vDegree
        let grevilleU = greville(knotsU, degree: layout.uDegree, count: uCount)
        let grevilleV = greville(knotsV, degree: layout.vDegree, count: vCount)
        let solverU = try BandedCollocation(knots: knotsU, degree: layout.uDegree, abscissae: grevilleU)
        let solverV = try BandedCollocation(knots: knotsV, degree: layout.vDegree, abscissae: grevilleV)
        // samples[j][i] = map at (grevilleU[i], grevilleV[j]).
        let samples = try grevilleV.map { t in try grevilleU.map { s in try point(s, t) } }
        // Along u for each v row, then along v for each u column.
        let rows = try samples.map { try solverU.solve($0) }
        var controlPoints = Array(repeating: Array(repeating: Point3D.origin, count: uCount), count: vCount)
        for i in 0..<uCount {
            let column = try solverV.solve(rows.map { $0[i] })
            for j in 0..<vCount { controlPoints[j][i] = column[j] }
        }
        let surface = BSplineSurface3D(uDegree: layout.uDegree, vDegree: layout.vDegree, uKnots: knotsU, vKnots: knotsV, controlPoints: controlPoints)
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
