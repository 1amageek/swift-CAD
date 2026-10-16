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
        var execution = try Self.independentExecution(maximumSpans: maximumSpanCount)
        return try fit(u: u, v: v, tolerance: tolerance, using: &execution) { u, v, _ in try point(u, v) }
    }

    package func fit(
        u: ScalarInterval, v: ScalarInterval, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution,
        point: (Double, Double, inout OriginalQueryExecution) throws -> Point3D
    ) throws -> Result {
        guard u.width > 0, v.width > 0, u.lower.isFinite, u.upper.isFinite, v.lower.isFinite, v.upper.isFinite else {
            throw KernelError(phase: .validation, code: .invalidInput, tolerance: tolerance,
                message: "A surface fit needs a finite parameter rectangle of positive extent.")
        }
        // One span first: a map that is affine over the rectangle is fitted exactly by it.
        var spans = (u: 1, v: 1)
        var result = try Self.fit(layout: layout(1, 1), u: u, v: v, tolerance: tolerance, using: &execution, point: point)
        while result.maximumDeviation > deviation {
            var candidates: [((u: Int, v: Int), Result)] = []
            if spans.u < maximumSpanCount {
                let next = (u: min(spans.u * 2, maximumSpanCount), v: spans.v)
                candidates.append((next, try Self.fit(layout: layout(next.u, next.v), u: u, v: v, tolerance: tolerance, using: &execution, point: point)))
            }
            if spans.v < maximumSpanCount {
                let next = (u: spans.u, v: min(spans.v * 2, maximumSpanCount))
                candidates.append((next, try Self.fit(layout: layout(next.u, next.v), u: u, v: v, tolerance: tolerance, using: &execution, point: point)))
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
                result = try Self.fit(layout: layout(spans.u, spans.v), u: u, v: v, tolerance: tolerance, using: &execution, point: point)
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
        var execution = try independentExecution(maximumSpans: GeometryConversionDimensions.product(layout.uSpans, layout.vSpans))
        return try fit(layout: layout, u: u, v: v, tolerance: tolerance, using: &execution) { u, v, _ in try point(u, v) }
    }

    package static func fit(
        layout: Layout, u: ScalarInterval, v: ScalarInterval, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution,
        point: (Double, Double, inout OriginalQueryExecution) throws -> Point3D
    ) throws -> Result {
        guard layout.uDegree >= 1, layout.vDegree >= 1, layout.uSpans >= 1, layout.vSpans >= 1,
            u.lower.isFinite, u.upper.isFinite, u.width.isFinite, u.width > 0,
            v.lower.isFinite, v.upper.isFinite, v.width.isFinite, v.width > 0 else {
            throw GeometryConversionError.invalidInput("A surface fit requires finite positive parameter spans, degrees and layout counts.")
        }
        let uCount = try sum(layout.uSpans, layout.uDegree)
        let vCount = try sum(layout.vSpans, layout.vDegree)
        let spans = try GeometryConversionDimensions.product(layout.uSpans, layout.vSpans)
        guard spans <= execution.limits.maximumSpans else {
            throw GeometryConversionError.resourceLimitExceeded("Surface construction exceeds caller span admission.")
        }
        let knotsU = try clampedUniformKnots(spans: layout.uSpans, on: u, degree: layout.uDegree, using: &execution)
        let knotsV = try clampedUniformKnots(spans: layout.vSpans, on: v, degree: layout.vDegree, using: &execution)
        let grevilleU = try greville(knotsU, degree: layout.uDegree, count: uCount, using: &execution)
        let grevilleV = try greville(knotsV, degree: layout.vDegree, count: vCount, using: &execution)
        let solverU = try BandedCollocation(knots: knotsU, degree: layout.uDegree, abscissae: grevilleU, using: &execution)
        let solverV = try BandedCollocation(knots: knotsV, degree: layout.vDegree, abscissae: grevilleV, using: &execution)
        try reserve(vCount, of: [Point3D].self, using: &execution)
        var rows: [[Point3D]] = []; rows.reserveCapacity(vCount)
        for t in grevilleV {
            try reserve(uCount, of: Point3D.self, using: &execution)
            var samples: [Point3D] = []; samples.reserveCapacity(uCount)
            for s in grevilleU {
                try execution.consumeWork(1)
                let sample = try point(s, t, &execution)
                guard sample.isFinite else { throw GeometryConversionError.invalidInput("A surface construction sample is nonfinite.") }
                samples.append(sample)
            }
            rows.append(try solverU.solve(samples, using: &execution))
        }
        try reserve(vCount, of: [Point3D].self, using: &execution)
        var controlPoints: [[Point3D]] = []; controlPoints.reserveCapacity(vCount)
        for _ in 0..<vCount {
            try reserve(uCount, of: Point3D.self, using: &execution)
            controlPoints.append(Array(repeating: .origin, count: uCount))
        }
        for i in 0..<uCount {
            try reserve(vCount, of: Point3D.self, using: &execution)
            var column: [Point3D] = []; column.reserveCapacity(vCount)
            for row in rows { try execution.consumeWork(1); column.append(row[i]) }
            let solved = try solverV.solve(column, using: &execution)
            for j in 0..<vCount { try execution.consumeWork(1); controlPoints[j][i] = solved[j] }
        }
        try reserve(vCount, of: [Double].self, using: &execution)
        var weights: [[Double]] = []; weights.reserveCapacity(vCount)
        for _ in 0..<vCount {
            try reserve(uCount, of: Double.self, using: &execution)
            weights.append(Array(repeating: 1, count: uCount))
        }
        let surface = BSplineSurface3D(uDegree: layout.uDegree, vDegree: layout.vDegree,
            uKnots: knotsU, vKnots: knotsV, controlPoints: controlPoints, weights: weights)
        func check(_ s: Double, _ t: Double, using execution: inout OriginalQueryExecution) throws -> Double {
            try execution.consumeWork(1)
            let bu = try candidateBasis(parameter: s, degree: layout.uDegree, knots: knotsU, count: uCount, using: &execution)
            let bv = try candidateBasis(parameter: t, degree: layout.vDegree, knots: knotsV, count: vCount, using: &execution)
            var value = Vector3D.zero
            for j in bv.values.indices {
                for i in bu.values.indices {
                    try execution.consumeWork(1)
                    let p = controlPoints[bv.start + j][bu.start + i]
                    value = value + Vector3D(x: p.x, y: p.y, z: p.z) * (bu.values[i] * bv.values[j])
                }
            }
            let reference = try point(s, t, &execution)
            let distance = (Point3D(x: value.x, y: value.y, z: value.z) - reference).length
            guard distance.isFinite else { throw GeometryConversionError.resourceLimitExceeded("Surface candidate arithmetic is nonfinite.") }
            return distance
        }
        var maximum = 0.0
        for cellV in 0..<layout.vSpans {
            for cellU in 0..<layout.uSpans {
                for a in 0..<4 {
                    for b in 0..<4 {
                        let s = u.lower + u.width * (Double(cellU) + Double(a) * 0.25) / Double(layout.uSpans)
                        let t = v.lower + v.width * (Double(cellV) + Double(b) * 0.25) / Double(layout.vSpans)
                        maximum = max(maximum, try check(s, t, using: &execution))
                    }
                }
            }
        }
        let farV = try GeometryConversionDimensions.product(4, layout.vSpans)
        let farU = try GeometryConversionDimensions.product(4, layout.uSpans)
        for index in 0...farV {
            maximum = max(maximum, try check(u.upper, v.lower + v.width * Double(index) / Double(farV), using: &execution))
        }
        for index in 0...farU {
            maximum = max(maximum, try check(u.lower + u.width * Double(index) / Double(farU), v.upper, using: &execution))
        }
        try execution.checkpoint()
        return Result(surface: surface, maximumDeviation: maximum)
    }

    private static func independentExecution(maximumSpans: Int) throws -> OriginalQueryExecution {
        try OriginalQueryExecution(budget: OriginalQueryBudget(),
            limits: OriginalQueryExecutionLimits(maximumValueDepth: 32, maximumCoefficientDepth: 32,
                maximumSpans: maximumSpans))
    }

    fileprivate static func reserve<T>(_ count: Int, of: T.Type, using execution: inout OriginalQueryExecution) throws {
        try CurrentTaskCancellationChecker().checkCancellation()
        guard count >= 0 else { throw GeometryConversionError.resourceLimitExceeded("Candidate storage count is negative.") }
        try execution.retainStorage(bytes: GeometryConversionDimensions.product(count, MemoryLayout<T>.stride))
    }

    private static func sum(_ a: Int, _ b: Int) throws -> Int {
        let result = a.addingReportingOverflow(b)
        guard a >= 0, b >= 0, !result.overflow else {
            throw GeometryConversionError.resourceLimitExceeded("Surface candidate dimensions overflowed.")
        }
        return result.partialValue
    }

    private static func clampedUniformKnots(spans: Int, on interval: ScalarInterval, degree: Int,
        using execution: inout OriginalQueryExecution) throws -> [Double] {
        let count = try sum(try sum(spans, degree), try sum(degree, 1))
        try reserve(count, of: Double.self, using: &execution)
        var knots: [Double] = []; knots.reserveCapacity(count)
        for _ in 0...degree { try execution.consumeWork(1); knots.append(interval.lower) }
        if spans > 1 {
            for i in 1..<spans {
                try execution.consumeWork(1)
                let f = Double(i) / Double(spans)
                let value = (1 - f) * interval.lower + f * interval.upper
                guard value.isFinite else { throw GeometryConversionError.resourceLimitExceeded("A candidate knot is nonfinite.") }
                knots.append(value)
            }
        }
        for _ in 0...degree { try execution.consumeWork(1); knots.append(interval.upper) }
        return knots
    }

    private static func greville(_ knots: [Double], degree: Int, count: Int,
        using execution: inout OriginalQueryExecution) throws -> [Double] {
        try reserve(count, of: Double.self, using: &execution)
        var values: [Double] = []; values.reserveCapacity(count)
        for index in 0..<count {
            try execution.consumeWork(1)
            var average = knots[index + 1]
            for offset in 2...max(2, degree) where offset <= degree {
                try execution.consumeWork(1)
                // Candidate-only running means preserve constant endpoint knots.
                let f = 1 / Double(offset)
                average = (1 - f) * average + f * knots[index + offset]
            }
            average = min(max(average, knots[degree]), knots[count])
            guard average.isFinite else { throw GeometryConversionError.resourceLimitExceeded("A Greville construction station is nonfinite.") }
            values.append(average)
        }
        return values
    }

    /// Candidate arithmetic has no source-proof authority; its final whole
    /// certificate remains mandatory. This owner admits all recurrence buffers.
    fileprivate static func candidateBasis(parameter: Double, degree: Int, knots: [Double], count: Int,
        using execution: inout OriginalQueryExecution) throws -> (start: Int, values: [Double]) {
        guard parameter.isFinite, parameter >= knots[degree], parameter <= knots[count] else {
            throw GeometryConversionError.invalidInput("A construction station lies outside its candidate basis.")
        }
        var span = count - 1
        if parameter < knots[count] {
            var lower = degree, upper = count
            while lower + 1 < upper {
                try execution.consumeWork(1)
                let mid = lower + (upper - lower) / 2
                if parameter < knots[mid] { upper = mid } else { lower = mid }
            }
            span = lower
        }
        for _ in 0..<3 { try reserve(degree + 1, of: Double.self, using: &execution) }
        var values = Array(repeating: 0.0, count: degree + 1)
        var left = Array(repeating: 0.0, count: degree + 1)
        var right = Array(repeating: 0.0, count: degree + 1)
        values[0] = 1
        for j in 1...degree {
            try execution.consumeWork(1)
            left[j] = parameter - knots[span + 1 - j]
            right[j] = knots[span + j] - parameter
            var saved = 0.0
            for r in 0..<j {
                try execution.consumeWork(1)
                let divisor = right[r + 1] + left[j - r]
                guard divisor.isFinite, divisor > 0 else {
                    throw GeometryConversionError.invalidInput("The candidate basis has a collapsed owning span.")
                }
                let temporary = values[r] / divisor
                values[r] = saved + right[r + 1] * temporary
                saved = left[j - r] * temporary
            }
            values[j] = saved
        }
        return (span - degree, values)
    }
}

/// Candidate collocation factors retain flat owned buffers to avoid row COW
/// allocations during elimination. They never replace original source proof.
private struct BandedCollocation {
    private var lower: [Double]
    private var upper: [Double]
    private let count: Int

    init(knots: [Double], degree: Int, abscissae: [Double], using execution: inout OriginalQueryExecution) throws {
        count = abscissae.count
        let cells = try GeometryConversionDimensions.product(count, count)
        try MappedBSplineSurfaceFitter.reserve(cells, of: Double.self, using: &execution)
        lower = Array(repeating: 0, count: cells)
        try MappedBSplineSurfaceFitter.reserve(cells, of: Double.self, using: &execution)
        upper = Array(repeating: 0, count: cells)
        for row in abscissae.indices {
            let basis = try MappedBSplineSurfaceFitter.candidateBasis(parameter: abscissae[row],
                degree: degree, knots: knots, count: count, using: &execution)
            for offset in basis.values.indices {
                try execution.consumeWork(1)
                upper[row * count + basis.start + offset] = basis.values[offset]
            }
        }
        for pivot in 0..<count {
            try execution.consumeWork(1)
            guard upper[pivot * count + pivot].isFinite, abs(upper[pivot * count + pivot]) > 1e-14 else {
                throw GeometryConversionError.invalidInput("A surface candidate collocation matrix is singular.")
            }
            lower[pivot * count + pivot] = 1
            for row in (pivot + 1)..<count {
                try execution.consumeWork(1)
                guard upper[row * count + pivot] != 0 else { continue }
                let factor = upper[row * count + pivot] / upper[pivot * count + pivot]
                lower[row * count + pivot] = factor
                for column in pivot..<count {
                    try execution.consumeWork(1)
                    upper[row * count + column] -= factor * upper[pivot * count + column]
                }
            }
        }
    }

    func solve(_ values: [Point3D], using execution: inout OriginalQueryExecution) throws -> [Point3D] {
        guard values.count == count else { throw GeometryConversionError.invalidInput("Candidate collocation input count differs from its factors.") }
        try MappedBSplineSurfaceFitter.reserve(count, of: Vector3D.self, using: &execution)
        var forward: [Vector3D] = []; forward.reserveCapacity(count)
        for value in values { try execution.consumeWork(1); forward.append(.init(x: value.x, y: value.y, z: value.z)) }
        for row in 0..<count {
            for column in 0..<row {
                try execution.consumeWork(1)
                guard lower[row * count + column] != 0 else { continue }
                forward[row] = forward[row] - forward[column] * lower[row * count + column]
            }
        }
        try MappedBSplineSurfaceFitter.reserve(count, of: Vector3D.self, using: &execution)
        var solution = forward
        for row in stride(from: count - 1, through: 0, by: -1) {
            try execution.consumeWork(1)
            var value = forward[row]
            for column in (row + 1)..<count {
                try execution.consumeWork(1)
                guard upper[row * count + column] != 0 else { continue }
                value = value - solution[column] * upper[row * count + column]
            }
            solution[row] = value * (1 / upper[row * count + row])
        }
        try MappedBSplineSurfaceFitter.reserve(count, of: Point3D.self, using: &execution)
        var result: [Point3D] = []; result.reserveCapacity(count)
        for value in solution {
            try execution.consumeWork(1)
            let point = Point3D(x: value.x, y: value.y, z: value.z)
            guard point.isFinite else { throw GeometryConversionError.resourceLimitExceeded("Candidate interpolation coefficients are nonfinite.") }
            result.append(point)
        }
        return result
    }
}
