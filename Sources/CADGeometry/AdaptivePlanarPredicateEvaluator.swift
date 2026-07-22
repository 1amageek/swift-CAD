import Foundation
import CADCore

public struct AdaptivePlanarPredicateEvaluator: PlanarPredicateEvaluating {
    public init() {}

    public func orientation(
        _ start: Point2D,
        _ end: Point2D,
        relativeTo point: Point2D,
        tolerance: ModelingTolerance
    ) throws -> RobustSign {
        try validate([start, end, point], tolerance: tolerance)
        return try RobustPredicates.orientation2D(
            start,
            end,
            relativeTo: point,
            determinantTolerance: try determinantTolerance(
                start,
                end,
                point,
                tolerance: tolerance
            )
        )
    }

    public func orientation(
        of polygon: [Point2D],
        tolerance: ModelingTolerance
    ) throws -> RobustSign {
        try polygonAreaEvaluation(
            of: polygon,
            tolerance: tolerance
        ).orientation
    }

    public func certifiedSignedArea(
        of polygon: [Point2D],
        tolerance: ModelingTolerance
    ) throws -> Double {
        let evaluation = try polygonAreaEvaluation(
            of: polygon,
            tolerance: tolerance
        )
        guard evaluation.orientation == .positive
                || evaluation.orientation == .negative else {
            throw KernelError(
                phase: .classification,
                code: .classificationFailure,
                residual: evaluation.twiceAreaEstimate.isFinite
                    ? abs(evaluation.twiceAreaEstimate) * 0.5
                    : nil,
                tolerance: tolerance,
                message: "Planar polygon area could not be certified within tolerance."
            )
        }
        return evaluation.twiceAreaEstimate * 0.5
    }

    private func polygonAreaEvaluation(
        of polygon: [Point2D],
        tolerance: ModelingTolerance
    ) throws -> PolygonAreaEvaluation {
        try validate(polygon, tolerance: tolerance)
        guard polygon.count >= 3 else {
            throw KernelError(
                phase: .classification,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Planar polygon orientation requires at least three vertices."
            )
        }

        let origin = polygon[0]
        var twiceArea = [0.0]
        var scale = 0.0
        for index in 1..<(polygon.count - 1) {
            let firstX = FloatingPointExpansion.difference(polygon[index].x, origin.x)
            let firstY = FloatingPointExpansion.difference(polygon[index].y, origin.y)
            let secondX = FloatingPointExpansion.difference(polygon[index + 1].x, origin.x)
            let secondY = FloatingPointExpansion.difference(polygon[index + 1].y, origin.y)
            let triangle = FloatingPointExpansion.subtract(
                FloatingPointExpansion.product(firstX, secondY),
                FloatingPointExpansion.product(firstY, secondX)
            )
            twiceArea = FloatingPointExpansion.sum(twiceArea, triangle)
            scale = max(
                scale,
                max(
                    hypot(polygon[index].x - origin.x, polygon[index].y - origin.y),
                    hypot(polygon[index + 1].x - origin.x, polygon[index + 1].y - origin.y)
                )
            )
        }

        let exactSign = FloatingPointExpansion.sign(twiceArea)
        guard exactSign != .zero else {
            return PolygonAreaEvaluation(
                orientation: .zero,
                twiceAreaEstimate: 0.0
            )
        }
        guard exactSign != .indeterminate,
              scale.isFinite else {
            return PolygonAreaEvaluation(
                orientation: .indeterminate,
                twiceAreaEstimate: .nan
            )
        }
        let scaleSquared = scale * scale
        let areaTolerance = max(
            tolerance.distance * max(scale, tolerance.distance),
            tolerance.angle * scaleSquared,
            tolerance.relative * scaleSquared
        ) * 2.0
        let estimate = FloatingPointExpansion.estimate(twiceArea)
        guard areaTolerance.isFinite,
              estimate.isFinite,
              abs(estimate) > areaTolerance else {
            return PolygonAreaEvaluation(
                orientation: .indeterminate,
                twiceAreaEstimate: estimate
            )
        }
        return PolygonAreaEvaluation(
            orientation: exactSign,
            twiceAreaEstimate: estimate
        )
    }

    public func classify(
        _ point: Point2D,
        in polygon: [Point2D],
        tolerance: ModelingTolerance
    ) throws -> PlanarPointClassification {
        try validate(polygon + [point], tolerance: tolerance)
        guard polygon.count >= 3 else {
            throw KernelError(
                phase: .classification,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Planar point classification requires at least three polygon vertices."
            )
        }

        for index in polygon.indices {
            let start = polygon[index]
            let end = polygon[(index + 1) % polygon.count]
            if distance(point, toSegmentFrom: start, to: end) <= tolerance.distance {
                return .boundary
            }
        }

        var windingNumber = 0
        for index in polygon.indices {
            let start = polygon[index]
            let end = polygon[(index + 1) % polygon.count]
            let orientation = try exactOrientation(start, end, relativeTo: point)
            if orientation == .indeterminate {
                return .indeterminate
            }
            if start.y <= point.y {
                if end.y > point.y, orientation == .positive {
                    windingNumber += 1
                }
            } else if end.y <= point.y, orientation == .negative {
                windingNumber -= 1
            }
        }
        return windingNumber == 0 ? .outside : .inside
    }

    public func segmentsIntersectOrTouch(
        _ firstStart: Point2D,
        _ firstEnd: Point2D,
        _ secondStart: Point2D,
        _ secondEnd: Point2D,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        try validate(
            [firstStart, firstEnd, secondStart, secondEnd],
            tolerance: tolerance
        )
        guard boundingBoxesOverlap(
            firstStart,
            firstEnd,
            secondStart,
            secondEnd,
            tolerance: tolerance.distance
        ) else {
            return false
        }

        if distance(firstStart, toSegmentFrom: secondStart, to: secondEnd) <= tolerance.distance
            || distance(firstEnd, toSegmentFrom: secondStart, to: secondEnd) <= tolerance.distance
            || distance(secondStart, toSegmentFrom: firstStart, to: firstEnd) <= tolerance.distance
            || distance(secondEnd, toSegmentFrom: firstStart, to: firstEnd) <= tolerance.distance {
            return true
        }

        let firstStartSign = try exactOrientation(
            secondStart,
            secondEnd,
            relativeTo: firstStart
        )
        let firstEndSign = try exactOrientation(
            secondStart,
            secondEnd,
            relativeTo: firstEnd
        )
        let secondStartSign = try exactOrientation(
            firstStart,
            firstEnd,
            relativeTo: secondStart
        )
        let secondEndSign = try exactOrientation(
            firstStart,
            firstEnd,
            relativeTo: secondEnd
        )
        guard [firstStartSign, firstEndSign, secondStartSign, secondEndSign]
            .contains(.indeterminate) == false else {
            throw KernelError(
                phase: .classification,
                code: .classificationFailure,
                tolerance: tolerance,
                message: "Adaptive segment intersection could not resolve an exact orientation."
            )
        }
        return opposite(firstStartSign, firstEndSign)
            && opposite(secondStartSign, secondEndSign)
    }

    public func areCollinear(
        _ firstStart: Point2D,
        _ firstEnd: Point2D,
        _ secondStart: Point2D,
        _ secondEnd: Point2D,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        try validate(
            [firstStart, firstEnd, secondStart, secondEnd],
            tolerance: tolerance
        )
        let length = hypot(firstEnd.x - firstStart.x, firstEnd.y - firstStart.y)
        guard length > tolerance.distance else {
            return false
        }
        return lineDistance(secondStart, from: firstStart, to: firstEnd) <= tolerance.distance
            && lineDistance(secondEnd, from: firstStart, to: firstEnd) <= tolerance.distance
    }

    private func exactOrientation(
        _ start: Point2D,
        _ end: Point2D,
        relativeTo point: Point2D
    ) throws -> RobustSign {
        try RobustPredicates.orientation2D(
            start,
            end,
            relativeTo: point,
            determinantTolerance: 0.0
        )
    }

    private func determinantTolerance(
        _ start: Point2D,
        _ end: Point2D,
        _ point: Point2D,
        tolerance: ModelingTolerance
    ) throws -> Double {
        let firstLength = hypot(end.x - start.x, end.y - start.y)
        let secondLength = hypot(point.x - start.x, point.y - start.y)
        let lengthProduct = firstLength * secondLength
        let value = max(
            tolerance.distance * max(1.0, max(firstLength, secondLength)),
            tolerance.angle * lengthProduct,
            tolerance.relative * lengthProduct
        )
        guard value.isFinite else {
            throw KernelError(
                phase: .classification,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Planar orientation scale exceeds the finite numeric domain."
            )
        }
        return value
    }

    private func validate(
        _ points: [Point2D],
        tolerance: ModelingTolerance
    ) throws {
        try tolerance.validate()
        guard points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else {
            throw KernelError(
                phase: .classification,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Planar predicates require finite points."
            )
        }
    }

    private func distance(
        _ point: Point2D,
        toSegmentFrom start: Point2D,
        to end: Point2D
    ) -> Double {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length > 0.0, length.isFinite else {
            return hypot(point.x - start.x, point.y - start.y)
        }
        let unitX = dx / length
        let unitY = dy / length
        let parameter = max(
            0.0,
            min(
                length,
                (point.x - start.x) * unitX + (point.y - start.y) * unitY
            )
        )
        return hypot(
            point.x - (start.x + parameter * unitX),
            point.y - (start.y + parameter * unitY)
        )
    }

    private func lineDistance(
        _ point: Point2D,
        from start: Point2D,
        to end: Point2D
    ) -> Double {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length > 0.0, length.isFinite else {
            return hypot(point.x - start.x, point.y - start.y)
        }
        let unitX = dx / length
        let unitY = dy / length
        return abs(unitX * (point.y - start.y) - unitY * (point.x - start.x))
    }

    private func boundingBoxesOverlap(
        _ firstStart: Point2D,
        _ firstEnd: Point2D,
        _ secondStart: Point2D,
        _ secondEnd: Point2D,
        tolerance: Double
    ) -> Bool {
        max(firstStart.x, firstEnd.x) + tolerance >= min(secondStart.x, secondEnd.x)
            && max(secondStart.x, secondEnd.x) + tolerance >= min(firstStart.x, firstEnd.x)
            && max(firstStart.y, firstEnd.y) + tolerance >= min(secondStart.y, secondEnd.y)
            && max(secondStart.y, secondEnd.y) + tolerance >= min(firstStart.y, firstEnd.y)
    }

    private func opposite(_ first: RobustSign, _ second: RobustSign) -> Bool {
        (first == .negative && second == .positive)
            || (first == .positive && second == .negative)
    }

    private struct PolygonAreaEvaluation {
        let orientation: RobustSign
        let twiceAreaEstimate: Double
    }
}
