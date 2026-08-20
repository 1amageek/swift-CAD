import CADCore

public struct CubicBezierSplineTessellator: Sendable {
    struct Sample: Sendable {
        let parameter: Double
        let point: Point2D
    }

    private let tolerance: ModelingTolerance
    private let maximumSubdivisionDepth: Int
    private let maximumPointCount: Int

    public init(
        tolerance: ModelingTolerance,
        maximumSubdivisionDepth: Int = 16,
        maximumPointCount: Int = 8_192
    ) {
        self.tolerance = tolerance
        self.maximumSubdivisionDepth = maximumSubdivisionDepth
        self.maximumPointCount = maximumPointCount
    }

    public func points(for controlPoints: [Point2D]) throws -> [Point2D] {
        try samples(for: controlPoints).map(\.point)
    }

    func samples(for controlPoints: [Point2D]) throws -> [Sample] {
        try tolerance.validate()
        guard maximumSubdivisionDepth > 0, maximumPointCount >= 4 else {
            throw GeometryError.invalidTolerance(distance: tolerance.distance, angle: tolerance.angle)
        }
        guard controlPoints.count >= 4, (controlPoints.count - 1).isMultiple(of: 3) else {
            throw SketchError.unsupportedEntity(
                "Cubic sketch spline control point count must be 3n + 1 and at least 4."
            )
        }
        for point in controlPoints {
            guard point.x.isFinite, point.y.isFinite else {
                throw GeometryError.invalidCoordinate(point.x.isFinite ? point.y : point.x)
            }
        }

        var samples = [Sample(parameter: 0.0, point: controlPoints[0])]
        for segmentStart in stride(from: 0, to: controlPoints.count - 1, by: 3) {
            let segmentIndex = segmentStart / 3
            try appendFlattenedCubic(
                controlPoints[segmentStart],
                controlPoints[segmentStart + 1],
                controlPoints[segmentStart + 2],
                controlPoints[segmentStart + 3],
                lowerParameter: Double(segmentIndex),
                upperParameter: Double(segmentIndex + 1),
                depth: 0,
                samples: &samples
            )
        }
        guard samples.count >= 2 else {
            throw SketchError.degenerateProfile
        }
        return samples
    }

    private func appendFlattenedCubic(
        _ p0: Point2D,
        _ p1: Point2D,
        _ p2: Point2D,
        _ p3: Point2D,
        lowerParameter: Double,
        upperParameter: Double,
        depth: Int,
        samples: inout [Sample]
    ) throws {
        guard distance(p0, p3) > tolerance.distance else {
            throw SketchError.degenerateProfile
        }
        let flatness = max(
            distanceFromLine(point: p1, lineStart: p0, lineEnd: p3),
            distanceFromLine(point: p2, lineStart: p0, lineEnd: p3)
        )
        if flatness <= tolerance.distance {
            try append(
                Sample(parameter: upperParameter, point: p3),
                to: &samples
            )
            return
        }
        guard depth < maximumSubdivisionDepth else {
            throw SketchError.unsupportedProfile(
                "Spline profile requires more subdivisions at the current modeling tolerance."
            )
        }

        let p01 = midpoint(p0, p1)
        let p12 = midpoint(p1, p2)
        let p23 = midpoint(p2, p3)
        let p012 = midpoint(p01, p12)
        let p123 = midpoint(p12, p23)
        let center = midpoint(p012, p123)
        let centerParameter = midpoint(lowerParameter, upperParameter)
        try appendFlattenedCubic(
            p0,
            p01,
            p012,
            center,
            lowerParameter: lowerParameter,
            upperParameter: centerParameter,
            depth: depth + 1,
            samples: &samples
        )
        try appendFlattenedCubic(
            center,
            p123,
            p23,
            p3,
            lowerParameter: centerParameter,
            upperParameter: upperParameter,
            depth: depth + 1,
            samples: &samples
        )
    }

    private func append(_ sample: Sample, to samples: inout [Sample]) throws {
        if let last = samples.last,
           distance(last.point, sample.point) <= tolerance.distance {
            return
        }
        guard samples.count < maximumPointCount else {
            throw SketchError.unsupportedProfile(
                "Spline profile requires more than \(maximumPointCount) tessellation points."
            )
        }
        samples.append(sample)
    }

    private func midpoint(_ lhs: Point2D, _ rhs: Point2D) -> Point2D {
        Point2D(
            x: (lhs.x + rhs.x) * 0.5,
            y: (lhs.y + rhs.y) * 0.5
        )
    }

    private func midpoint(_ lhs: Double, _ rhs: Double) -> Double {
        lhs + (rhs - lhs) * 0.5
    }

    private func distance(_ lhs: Point2D, _ rhs: Point2D) -> Double {
        let dx = lhs.x - rhs.x
        let dy = lhs.y - rhs.y
        return (dx * dx + dy * dy).squareRoot()
    }

    private func distanceFromLine(
        point: Point2D,
        lineStart: Point2D,
        lineEnd: Point2D
    ) -> Double {
        let dx = lineEnd.x - lineStart.x
        let dy = lineEnd.y - lineStart.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > tolerance.distance else {
            return distance(point, lineStart)
        }
        let offsetX = point.x - lineStart.x
        let offsetY = point.y - lineStart.y
        return abs(dx * offsetY - dy * offsetX) / length
    }
}
