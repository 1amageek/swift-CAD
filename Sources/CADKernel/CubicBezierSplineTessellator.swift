import CADCore

public struct CubicBezierSplineTessellator: Sendable {
    private let tolerance: ModelingTolerance
    private let maximumSubdivisionDepth: Int
    private let maximumPointCount: Int

    public init(
        tolerance: ModelingTolerance = .standard,
        maximumSubdivisionDepth: Int = 16,
        maximumPointCount: Int = 8_192
    ) {
        self.tolerance = tolerance
        self.maximumSubdivisionDepth = maximumSubdivisionDepth
        self.maximumPointCount = maximumPointCount
    }

    public func points(for controlPoints: [Point2D]) throws -> [Point2D] {
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

        var points = [controlPoints[0]]
        for segmentStart in stride(from: 0, to: controlPoints.count - 1, by: 3) {
            try appendFlattenedCubic(
                controlPoints[segmentStart],
                controlPoints[segmentStart + 1],
                controlPoints[segmentStart + 2],
                controlPoints[segmentStart + 3],
                depth: 0,
                points: &points
            )
        }
        guard points.count >= 2 else {
            throw SketchError.degenerateProfile
        }
        return points
    }

    private func appendFlattenedCubic(
        _ p0: Point2D,
        _ p1: Point2D,
        _ p2: Point2D,
        _ p3: Point2D,
        depth: Int,
        points: inout [Point2D]
    ) throws {
        guard distance(p0, p3) > tolerance.distance else {
            throw SketchError.degenerateProfile
        }
        let flatness = max(
            distanceFromLine(point: p1, lineStart: p0, lineEnd: p3),
            distanceFromLine(point: p2, lineStart: p0, lineEnd: p3)
        )
        if flatness <= tolerance.distance {
            try append(p3, to: &points)
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
        try appendFlattenedCubic(
            p0,
            p01,
            p012,
            center,
            depth: depth + 1,
            points: &points
        )
        try appendFlattenedCubic(
            center,
            p123,
            p23,
            p3,
            depth: depth + 1,
            points: &points
        )
    }

    private func append(_ point: Point2D, to points: inout [Point2D]) throws {
        if let last = points.last, distance(last, point) <= tolerance.distance {
            return
        }
        guard points.count < maximumPointCount else {
            throw SketchError.unsupportedProfile(
                "Spline profile requires more than \(maximumPointCount) tessellation points."
            )
        }
        points.append(point)
    }

    private func midpoint(_ lhs: Point2D, _ rhs: Point2D) -> Point2D {
        Point2D(
            x: (lhs.x + rhs.x) * 0.5,
            y: (lhs.y + rhs.y) * 0.5
        )
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
