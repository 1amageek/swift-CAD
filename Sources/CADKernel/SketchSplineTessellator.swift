import CADCore

/// Flattens a sketch spline of any degree into points within the modeling distance: each
/// Bezier segment is halved by de Casteljau until its interior control points lie within the
/// distance of its chord, which bounds the curve by the convex hull.
public struct SketchSplineTessellator: Sendable {
    public struct Sample: Sendable, Hashable {
        public let parameter: Double
        public let point: Point2D
    }

    private let tolerance: ModelingTolerance
    private let maximumSubdivisionDepth: Int
    private let maximumPointCount: Int

    public init(tolerance: ModelingTolerance, maximumSubdivisionDepth: Int = 16, maximumPointCount: Int = 8_192) {
        self.tolerance = tolerance
        self.maximumSubdivisionDepth = maximumSubdivisionDepth
        self.maximumPointCount = maximumPointCount
    }

    public func samples(for curve: SketchSplineCurve) throws -> [Sample] {
        try tolerance.validate()
        guard let first = curve.segments.first else { throw SketchError.degenerateProfile }
        var samples = [Sample(parameter: first.lowerParameter, point: first.controlPoints[0])]
        for segment in curve.segments {
            try appendFlattened(
                segment.controlPoints,
                lower: segment.lowerParameter,
                upper: segment.upperParameter,
                depth: 0,
                samples: &samples
            )
        }
        guard samples.count >= 2 else { throw SketchError.degenerateProfile }
        return samples
    }

    private func appendFlattened(
        _ points: [Point2D],
        lower: Double,
        upper: Double,
        depth: Int,
        samples: inout [Sample]
    ) throws {
        let start = points[0], end = points[points.count - 1]
        let flatness = points.dropFirst().dropLast().map { distanceFromChord($0, start, end) }.max() ?? 0
        if flatness <= tolerance.distance {
            try append(Sample(parameter: upper, point: end), to: &samples)
            return
        }
        guard depth < maximumSubdivisionDepth else {
            throw SketchError.unsupportedProfile("Spline profile requires more subdivisions at the current modeling tolerance.")
        }
        // de Casteljau at the middle: the left half is the first point of every level, the right
        // half the last, in reverse level order.
        var level = points
        var left = [points[0]]
        var right = [points[points.count - 1]]
        while level.count > 1 {
            level = zip(level, level.dropFirst()).map { Point2D(x: ($0.x + $1.x) * 0.5, y: ($0.y + $1.y) * 0.5) }
            left.append(level[0])
            right.append(level[level.count - 1])
        }
        let middle = lower + (upper - lower) * 0.5
        try appendFlattened(left, lower: lower, upper: middle, depth: depth + 1, samples: &samples)
        try appendFlattened(right.reversed(), lower: middle, upper: upper, depth: depth + 1, samples: &samples)
    }

    private func append(_ sample: Sample, to samples: inout [Sample]) throws {
        if let last = samples.last, distance(last.point, sample.point) <= tolerance.distance { return }
        guard samples.count < maximumPointCount else {
            throw SketchError.unsupportedProfile("Spline profile requires more than \(maximumPointCount) tessellation points.")
        }
        samples.append(sample)
    }

    private func distance(_ a: Point2D, _ b: Point2D) -> Double {
        ((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)).squareRoot()
    }

    /// The distance from `point` to the chord from `start` to `end`, or to `start` when the chord
    /// is shorter than the modeling distance (a segment that returns to its start).
    private func distanceFromChord(_ point: Point2D, _ start: Point2D, _ end: Point2D) -> Double {
        let dx = end.x - start.x, dy = end.y - start.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > tolerance.distance else { return distance(point, start) }
        return abs(dx * (point.y - start.y) - dy * (point.x - start.x)) / length
    }
}
