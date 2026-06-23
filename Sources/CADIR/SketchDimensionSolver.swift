import Foundation
import CADCore

public struct SketchDimensionSolver: Sendable {
    private let parameters: ParameterTable
    private let evaluator: SketchDimensionEvaluator

    public init(parameters: ParameterTable = ParameterTable()) {
        self.parameters = parameters
        self.evaluator = SketchDimensionEvaluator(parameters: parameters)
    }

    public func solve(
        _ sketch: Sketch,
        tolerance: ModelingTolerance = .standard
    ) throws -> SketchDimensionSolveResult {
        try tolerance.validate()
        let before = try evaluator.evaluate(sketch, tolerance: tolerance)
        var solvedSketch = sketch
        var steps: [SketchDimensionSolveStep] = []
        steps.reserveCapacity(sketch.dimensions.count)

        for measurement in before.measurements {
            if try measurement.isSatisfied(tolerance: tolerance) {
                steps.append(SketchDimensionSolveStep(
                    dimension: measurement.dimension,
                    status: .alreadySatisfied
                ))
                continue
            }

            let outcome = try apply(measurement.dimension, to: &solvedSketch, tolerance: tolerance)
            steps.append(outcome)
        }

        let after = try evaluator.evaluate(solvedSketch, tolerance: tolerance)
        return SketchDimensionSolveResult(
            sketch: solvedSketch,
            before: before,
            after: after,
            steps: steps
        )
    }

    private func apply(
        _ dimension: SketchDimension,
        to sketch: inout Sketch,
        tolerance: ModelingTolerance
    ) throws -> SketchDimensionSolveStep {
        switch dimension {
        case let .radius(entityID, value):
            try setRadius(value, on: entityID, in: &sketch)
            return SketchDimensionSolveStep(dimension: dimension, status: .applied)
        case let .diameter(entityID, value):
            try setRadius(.divide(value, .constant(.scalar(2.0))), on: entityID, in: &sketch)
            return SketchDimensionSolveStep(dimension: dimension, status: .applied)
        case let .distance(from, to, value):
            return try applyDistance(
                from: from,
                to: to,
                value: value,
                dimension: dimension,
                sketch: &sketch,
                tolerance: tolerance
            )
        case let .angle(from, to, value):
            return try applyAngle(
                from: from,
                to: to,
                value: value,
                dimension: dimension,
                sketch: &sketch,
                tolerance: tolerance
            )
        }
    }

    private func applyDistance(
        from: SketchReference,
        to: SketchReference,
        value: CADExpression,
        dimension: SketchDimension,
        sketch: inout Sketch,
        tolerance: ModelingTolerance
    ) throws -> SketchDimensionSolveStep {
        guard case let .lineStart(firstID) = from,
              case let .lineEnd(secondID) = to,
              firstID == secondID else {
            return SketchDimensionSolveStep(
                dimension: dimension,
                status: .unsupported,
                reason: "Direct distance solving currently supports line start-to-end dimensions."
            )
        }
        let target = try targetLength(value, operation: "sketch.dimension.distance")
        guard target > tolerance.distance else {
            throw GeometryError.invalidDistance(target)
        }
        let line = try line(firstID, in: sketch)
        let start = try resolved(line.start)
        let end = try resolved(line.end)
        let currentLength = hypot(end.x - start.x, end.y - start.y)
        guard currentLength > tolerance.distance else {
            throw GeometryError.invalidVectorLength(currentLength)
        }
        let directionX = (end.x - start.x) / currentLength
        let directionY = (end.y - start.y) / currentLength
        try setLineEnd(
            Point2D(x: start.x + directionX * target, y: start.y + directionY * target),
            on: firstID,
            in: &sketch
        )
        return SketchDimensionSolveStep(dimension: dimension, status: .applied)
    }

    private func applyAngle(
        from: SketchReference,
        to: SketchReference,
        value: CADExpression,
        dimension: SketchDimension,
        sketch: inout Sketch,
        tolerance: ModelingTolerance
    ) throws -> SketchDimensionSolveStep {
        if case let .lineStart(firstID) = from,
           case let .lineEnd(secondID) = to,
           firstID == secondID {
            let target = try targetAngle(value, operation: "sketch.dimension.angle")
            let line = try line(firstID, in: sketch)
            let start = try resolved(line.start)
            let end = try resolved(line.end)
            let length = hypot(end.x - start.x, end.y - start.y)
            guard length > tolerance.distance else {
                throw GeometryError.invalidVectorLength(length)
            }
            try setLineEnd(
                Point2D(x: start.x + cos(target) * length, y: start.y + sin(target) * length),
                on: firstID,
                in: &sketch
            )
            return SketchDimensionSolveStep(dimension: dimension, status: .applied)
        }

        if case let .arcStart(firstID) = from,
           case let .arcEnd(secondID) = to,
           firstID == secondID {
            var arc = try arc(firstID, in: sketch)
            arc.endAngle = .add(arc.startAngle, value)
            sketch.entities[firstID] = .arc(arc)
            return SketchDimensionSolveStep(dimension: dimension, status: .applied)
        }

        if case let .arcEnd(firstID) = from,
           case let .arcStart(secondID) = to,
           firstID == secondID {
            var arc = try arc(firstID, in: sketch)
            arc.startAngle = .add(arc.endAngle, value)
            sketch.entities[firstID] = .arc(arc)
            return SketchDimensionSolveStep(dimension: dimension, status: .applied)
        }

        return SketchDimensionSolveStep(
            dimension: dimension,
            status: .unsupported,
            reason: "Direct angle solving currently supports line orientation and arc span dimensions."
        )
    }

    private func setRadius(
        _ expression: CADExpression,
        on entityID: SketchEntityID,
        in sketch: inout Sketch
    ) throws {
        guard let entity = sketch.entities[entityID] else {
            throw SketchError.invalidReference("Circular reference points to a missing entity.")
        }
        switch entity {
        case .circle(var circle):
            circle.radius = expression
            sketch.entities[entityID] = .circle(circle)
        case .arc(var arc):
            arc.radius = expression
            sketch.entities[entityID] = .arc(arc)
        case .point, .line, .spline:
            throw SketchError.invalidReference("Dimension radius reference must point to a circular entity.")
        }
    }

    private func setLineEnd(
        _ point: Point2D,
        on entityID: SketchEntityID,
        in sketch: inout Sketch
    ) throws {
        var updated = try line(entityID, in: sketch)
        updated.end = sketchPoint(point)
        sketch.entities[entityID] = .line(updated)
    }

    private func line(_ entityID: SketchEntityID, in sketch: Sketch) throws -> SketchLine {
        guard let entity = sketch.entities[entityID],
              case let .line(line) = entity else {
            throw SketchError.invalidReference("Sketch reference must point to a line entity.")
        }
        return line
    }

    private func arc(_ entityID: SketchEntityID, in sketch: Sketch) throws -> SketchArc {
        guard let entity = sketch.entities[entityID],
              case let .arc(arc) = entity else {
            throw SketchError.invalidReference("Sketch reference must point to an arc entity.")
        }
        return arc
    }

    private func resolved(_ point: SketchPoint) throws -> Point2D {
        Point2D(
            x: try targetLength(point.x, operation: "sketch.point.x"),
            y: try targetLength(point.y, operation: "sketch.point.y")
        )
    }

    private func sketchPoint(_ point: Point2D) -> SketchPoint {
        SketchPoint(
            x: .constant(.length(point.x, unit: .meter)),
            y: .constant(.length(point.y, unit: .meter))
        )
    }

    private func targetLength(_ expression: CADExpression, operation: String) throws -> Double {
        let quantity = try parameters.resolvedValue(for: expression)
        guard quantity.kind == .length else {
            throw UnitError.expectedQuantity(operation: operation, expected: .length, actual: quantity.kind)
        }
        return quantity.value
    }

    private func targetAngle(_ expression: CADExpression, operation: String) throws -> Double {
        let quantity = try parameters.resolvedValue(for: expression)
        guard quantity.kind == .angle else {
            throw UnitError.expectedQuantity(operation: operation, expected: .angle, actual: quantity.kind)
        }
        return quantity.value
    }
}
