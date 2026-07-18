import Foundation
import CADCore

struct StrictlyConvexPlanarLoop {
    let points: [Point2D]

    private let orientationSign: Double

    init(points: [Point2D], tolerance: ModelingTolerance) throws {
        guard points.count >= 3 else {
            throw KernelError.unsupportedEvaluation(tolerance: tolerance, message:
                "Exact planar offset requires at least three polygon points."
            )
        }
        let signedArea = Self.signedArea(points)
        guard abs(signedArea) > tolerance.distance * tolerance.distance else {
            throw FeatureEvaluationError.invalidDistance(abs(signedArea))
        }
        orientationSign = signedArea > 0.0 ? 1.0 : -1.0
        self.points = points

        let directions = try points.indices.map { index in
            try Self.normalized(
                Self.subtract(points[(index + 1) % points.count], points[index]),
                tolerance: tolerance
            )
        }
        for index in directions.indices {
            let nextIndex = (index + 1) % directions.count
            guard Self.cross(directions[index], directions[nextIndex]) * orientationSign
                    > tolerance.angle else {
                throw KernelError.unsupportedEvaluation(tolerance: tolerance, message:
                    "Exact planar offset requires a strictly convex line loop."
                )
            }
        }
    }

    func inset(
        distance: Double,
        tolerance: ModelingTolerance
    ) throws -> [Point2D] {
        let lines = try points.indices.map {
            try offsetLine(edgeAt: $0, distance: distance, tolerance: tolerance)
        }
        let inner = try points.indices.map { index in
            try Self.intersection(
                lines[(index + points.count - 1) % points.count],
                lines[index],
                tolerance: tolerance
            )
        }
        _ = try StrictlyConvexPlanarLoop(points: inner, tolerance: tolerance)
        for line in lines {
            for point in inner {
                guard halfspaceResidual(point, relativeTo: line) >= -tolerance.distance else {
                    throw FeatureEvaluationError.invalidDistance(distance)
                }
            }
        }
        return inner
    }

    func offsetBoundary(
        edgeAt index: Int,
        distance: Double,
        tolerance: ModelingTolerance
    ) throws -> (start: Point2D, end: Point2D) {
        guard points.indices.contains(index) else {
            throw KernelError.unsupportedEvaluation(tolerance: tolerance, message:
                "Exact planar edge offset requires a valid boundary edge index."
            )
        }
        let previousIndex = (index + points.count - 1) % points.count
        let nextIndex = (index + 1) % points.count
        let previous = try offsetLine(edgeAt: previousIndex, distance: 0.0, tolerance: tolerance)
        let selected = try offsetLine(edgeAt: index, distance: distance, tolerance: tolerance)
        let next = try offsetLine(edgeAt: nextIndex, distance: 0.0, tolerance: tolerance)
        let start = try Self.intersection(previous, selected, tolerance: tolerance)
        let end = try Self.intersection(selected, next, tolerance: tolerance)
        guard contains(start, tolerance: tolerance),
              contains(end, tolerance: tolerance),
              hypot(end.x - start.x, end.y - start.y) > tolerance.distance else {
            throw FeatureEvaluationError.invalidDistance(distance)
        }
        return (start, end)
    }

    func contains(_ point: Point2D, tolerance: ModelingTolerance) -> Bool {
        for index in points.indices {
            let line = Line(
                point: points[index],
                direction: Self.subtract(points[(index + 1) % points.count], points[index])
            )
            guard halfspaceResidual(point, relativeTo: line) >= -tolerance.distance else {
                return false
            }
        }
        return true
    }

    private func offsetLine(
        edgeAt index: Int,
        distance: Double,
        tolerance: ModelingTolerance
    ) throws -> Line {
        let start = points[index]
        let direction = try Self.normalized(
            Self.subtract(points[(index + 1) % points.count], start),
            tolerance: tolerance
        )
        let inward = Point2D(
            x: -direction.y * orientationSign,
            y: direction.x * orientationSign
        )
        return Line(
            point: Point2D(
                x: start.x + inward.x * distance,
                y: start.y + inward.y * distance
            ),
            direction: direction
        )
    }

    private func halfspaceResidual(_ point: Point2D, relativeTo line: Line) -> Double {
        Self.cross(line.direction, Self.subtract(point, line.point)) * orientationSign
    }

    private static func intersection(
        _ first: Line,
        _ second: Line,
        tolerance: ModelingTolerance
    ) throws -> Point2D {
        let denominator = cross(first.direction, second.direction)
        guard abs(denominator) > tolerance.angle else {
            throw KernelError.unsupportedEvaluation(tolerance: tolerance, message:
                "Exact planar offset cannot intersect parallel adjacent boundary lines."
            )
        }
        let delta = subtract(second.point, first.point)
        let parameter = cross(delta, second.direction) / denominator
        return Point2D(
            x: first.point.x + first.direction.x * parameter,
            y: first.point.y + first.direction.y * parameter
        )
    }

    private static func normalized(
        _ vector: Point2D,
        tolerance: ModelingTolerance
    ) throws -> Point2D {
        let length = hypot(vector.x, vector.y)
        guard length > tolerance.distance else {
            throw FeatureEvaluationError.invalidDistance(length)
        }
        return Point2D(x: vector.x / length, y: vector.y / length)
    }

    private static func signedArea(_ points: [Point2D]) -> Double {
        var area = 0.0
        for index in points.indices {
            let current = points[index]
            let next = points[(index + 1) % points.count]
            area += current.x * next.y - next.x * current.y
        }
        return area * 0.5
    }

    private static func subtract(_ lhs: Point2D, _ rhs: Point2D) -> Point2D {
        Point2D(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }

    private static func cross(_ lhs: Point2D, _ rhs: Point2D) -> Double {
        lhs.x * rhs.y - lhs.y * rhs.x
    }

    private struct Line {
        let point: Point2D
        let direction: Point2D
    }
}
