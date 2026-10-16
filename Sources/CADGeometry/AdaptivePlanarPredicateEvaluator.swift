#if !hasFeature(Embedded)
import Foundation
#elseif canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#else
#error("CADGeometry numeric algorithms require the target C math module.")
#endif
import CADCore

public struct AdaptivePlanarPredicateEvaluator: PlanarPredicateEvaluating {
    public init() {}

    public func orientation(_ start: Point2D, _ end: Point2D, relativeTo point: Point2D,
        tolerance: ModelingTolerance) throws -> RobustSign {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try orientation(start, end, relativeTo: point, tolerance: tolerance, using: &execution)
    }
    public func orientation(of polygon: [Point2D], tolerance: ModelingTolerance) throws -> RobustSign {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try orientation(of: polygon, tolerance: tolerance, using: &execution)
    }
    public func certifiedSignedArea(of polygon: [Point2D], tolerance: ModelingTolerance) throws -> Double {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try certifiedSignedArea(of: polygon, tolerance: tolerance, using: &execution)
    }
    public func classify(_ point: Point2D, in polygon: [Point2D], tolerance: ModelingTolerance)
        throws -> PlanarPointClassification {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try classify(point, in: polygon, tolerance: tolerance, using: &execution)
    }
    public func segmentsIntersectOrTouch(_ a: Point2D, _ b: Point2D, _ c: Point2D, _ d: Point2D,
        tolerance: ModelingTolerance) throws -> Bool {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try segmentsIntersectOrTouch(a, b, c, d, tolerance: tolerance, using: &execution)
    }
    public func areCollinear(_ a: Point2D, _ b: Point2D, _ c: Point2D, _ d: Point2D,
        tolerance: ModelingTolerance) throws -> Bool {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try areCollinear(a, b, c, d, tolerance: tolerance, using: &execution)
    }


    public func orientation(
        _ start: Point2D,
        _ end: Point2D,
        relativeTo point: Point2D,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> RobustSign {
        try OriginalCoefficientAllocation.reserve(count: 3, of: Point2D.self, using: &execution)
        try validate([start, end, point], tolerance: tolerance, using: &execution)
        return try RobustPredicates.orientation2D(
            start,
            end,
            relativeTo: point,
            determinantTolerance: try determinantTolerance(
                start,
                end,
                point,
                tolerance: tolerance
            ), using: &execution
        )
    }

    public func orientation(
        of polygon: [Point2D],
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> RobustSign {
        try polygonAreaEvaluation(
            of: polygon,
            tolerance: tolerance, using: &execution
        ).orientation
    }

    public func certifiedSignedArea(
        of polygon: [Point2D],
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> Double {
        let evaluation = try polygonAreaEvaluation(
            of: polygon,
            tolerance: tolerance, using: &execution
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
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> PolygonAreaEvaluation {
        try validate(polygon, tolerance: tolerance, using: &execution)
        guard polygon.count >= 3 else {
            throw KernelError(
                phase: .classification,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Planar polygon orientation requires at least three vertices."
            )
        }

        let origin = polygon[0]
        try OriginalCoefficientAllocation.reserve(count: 1, of: Double.self, using: &execution)
        var twiceArea = [0.0]
        var scale = 0.0
        for index in 1..<(polygon.count - 1) {
            let firstX = try FloatingPointExpansion.difference(polygon[index].x, origin.x, using: &execution)
            let firstY = try FloatingPointExpansion.difference(polygon[index].y, origin.y, using: &execution)
            let secondX = try FloatingPointExpansion.difference(polygon[index + 1].x, origin.x, using: &execution)
            let secondY = try FloatingPointExpansion.difference(polygon[index + 1].y, origin.y, using: &execution)
            let triangle = try FloatingPointExpansion.subtract(
                FloatingPointExpansion.product(firstX, secondY, using: &execution),
                FloatingPointExpansion.product(firstY, secondX, using: &execution), using: &execution)
            twiceArea = try FloatingPointExpansion.sum(twiceArea, triangle, using: &execution)
            scale = max(
                scale,
                max(
                    hypot(polygon[index].x - origin.x, polygon[index].y - origin.y),
                    hypot(polygon[index + 1].x - origin.x, polygon[index + 1].y - origin.y)
                )
            )
        }

        let exactSign = try FloatingPointExpansion.sign(twiceArea, using: &execution)
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
        let estimate = try FloatingPointExpansion.estimate(twiceArea, using: &execution)
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
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> PlanarPointClassification {
        try validate(polygon, tolerance: tolerance, using: &execution)
        try execution.consumeWork(1)
        guard point.x.isFinite, point.y.isFinite else {
            throw KernelError(phase: .classification, code: .invalidInput,
                tolerance: tolerance, message: "Planar point classification requires finite coordinates.")
        }
        guard polygon.count >= 3 else {
            throw KernelError(
                phase: .classification,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Planar point classification requires at least three polygon vertices."
            )
        }

        for index in polygon.indices {
            try execution.consumeWork(1)
            let start = polygon[index]
            let end = polygon[(index + 1) % polygon.count]
            if distance(point, toSegmentFrom: start, to: end) <= tolerance.distance {
                return .boundary
            }
        }

        var windingNumber = 0
        for index in polygon.indices {
            try execution.consumeWork(1)
            let start = polygon[index]
            let end = polygon[(index + 1) % polygon.count]
            let orientation = try exactOrientation(start, end, relativeTo: point, using: &execution)
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
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> Bool {
        try OriginalCoefficientAllocation.reserve(count: 4, of: Point2D.self, using: &execution)
        try validate(
            [firstStart, firstEnd, secondStart, secondEnd],
            tolerance: tolerance, using: &execution
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
            relativeTo: firstStart, using: &execution
        )
        let firstEndSign = try exactOrientation(
            secondStart,
            secondEnd,
            relativeTo: firstEnd, using: &execution
        )
        let secondStartSign = try exactOrientation(
            firstStart,
            firstEnd,
            relativeTo: secondStart, using: &execution
        )
        let secondEndSign = try exactOrientation(
            firstStart,
            firstEnd,
            relativeTo: secondEnd, using: &execution
        )
        guard firstStartSign != .indeterminate, firstEndSign != .indeterminate,
            secondStartSign != .indeterminate, secondEndSign != .indeterminate else {
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
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> Bool {
        try OriginalCoefficientAllocation.reserve(count: 4, of: Point2D.self, using: &execution)
        try validate(
            [firstStart, firstEnd, secondStart, secondEnd],
            tolerance: tolerance, using: &execution
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
        relativeTo point: Point2D, using execution: inout OriginalQueryExecution
    ) throws -> RobustSign {
        try RobustPredicates.orientation2D(
            start,
            end,
            relativeTo: point,
            determinantTolerance: 0.0, using: &execution
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
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws {
        try tolerance.validate()
        for point in points {
            try execution.consumeWork(1)
            guard point.x.isFinite && point.y.isFinite else {
            throw KernelError(
                phase: .classification,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Planar predicates require finite points."
            )
            }
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
