import Foundation
import CADCore

public struct SketchDimensionEvaluator: Sendable {
    private let parameters: ParameterTable

    public init(parameters: ParameterTable = ParameterTable()) {
        self.parameters = parameters
    }

    public func evaluate(
        _ sketch: Sketch,
        tolerance: ModelingTolerance = .standard
    ) throws -> SketchDimensionEvaluation {
        try tolerance.validate()
        try sketch.validate(tolerance: tolerance)
        try sketch.validateExpressions(using: parameters)

        var measurements: [SketchDimensionMeasurement] = []
        measurements.reserveCapacity(sketch.dimensions.count)
        for dimension in sketch.dimensions {
            measurements.append(try measure(dimension, in: sketch, tolerance: tolerance))
        }
        return SketchDimensionEvaluation(measurements: measurements)
    }

    public func measure(
        _ dimension: SketchDimension,
        in sketch: Sketch,
        tolerance: ModelingTolerance = .standard
    ) throws -> SketchDimensionMeasurement {
        try tolerance.validate()
        let measured = try measuredQuantity(for: dimension, in: sketch, tolerance: tolerance)
        let target = try targetQuantity(for: dimension)
        guard measured.kind == target.kind else {
            throw UnitError.expectedQuantity(
                operation: "sketch.dimension.target",
                expected: measured.kind,
                actual: target.kind
            )
        }
        let residual = residualQuantity(measured: measured, target: target)
        return SketchDimensionMeasurement(
            dimension: dimension,
            measured: measured,
            target: target,
            residual: residual
        )
    }

    private func measuredQuantity(
        for dimension: SketchDimension,
        in sketch: Sketch,
        tolerance: ModelingTolerance
    ) throws -> Quantity {
        switch dimension {
        case let .distance(from, to, _):
            let first = try point(for: from, in: sketch)
            let second = try point(for: to, in: sketch)
            return .length(distance(from: first, to: second), unit: .meter)
        case let .angle(from, to, _):
            return .angle(try angle(from: from, to: to, in: sketch, tolerance: tolerance), unit: .radian)
        case let .radius(entityID, _):
            return .length(try radius(of: entityID, in: sketch), unit: .meter)
        case let .diameter(entityID, _):
            return .length(try radius(of: entityID, in: sketch) * 2.0, unit: .meter)
        }
    }

    private func targetQuantity(for dimension: SketchDimension) throws -> Quantity {
        switch dimension {
        case let .distance(_, _, value):
            return try target(value, expected: .length, operation: "sketch.dimension.distance")
        case let .angle(_, _, value):
            return try target(value, expected: .angle, operation: "sketch.dimension.angle")
        case let .radius(_, value):
            return try target(value, expected: .length, operation: "sketch.dimension.radius")
        case let .diameter(_, value):
            return try target(value, expected: .length, operation: "sketch.dimension.diameter")
        }
    }

    private func target(
        _ expression: CADExpression,
        expected: QuantityKind,
        operation: String
    ) throws -> Quantity {
        let quantity = try parameters.resolvedValue(for: expression)
        guard quantity.kind == expected else {
            throw UnitError.expectedQuantity(operation: operation, expected: expected, actual: quantity.kind)
        }
        return quantity
    }

    private func residualQuantity(measured: Quantity, target: Quantity) -> Quantity {
        switch measured.kind {
        case .angle:
            return Quantity(value: normalizedSignedAngle(measured.value - target.value), kind: .angle)
        case .length, .scalar:
            return Quantity(value: measured.value - target.value, kind: measured.kind)
        }
    }

    private func point(for reference: SketchReference, in sketch: Sketch) throws -> Point2D {
        switch reference {
        case let .entity(entityID):
            guard let entity = sketch.entities[entityID],
                  case let .point(point) = entity else {
                throw SketchError.invalidReference("Entity reference must point to a sketch point.")
            }
            return try resolved(point)
        case let .lineStart(entityID):
            return try resolved(line(entityID, in: sketch).start)
        case let .lineEnd(entityID):
            return try resolved(line(entityID, in: sketch).end)
        case let .circleCenter(entityID):
            return try resolved(circle(entityID, in: sketch).center)
        case .circleRadius:
            throw SketchError.invalidReference("Circle radius is not a point reference.")
        case let .arcCenter(entityID):
            return try resolved(arc(entityID, in: sketch).center)
        case let .arcStart(entityID):
            let arc = try arc(entityID, in: sketch)
            return try point(on: arc, at: arc.startAngle)
        case let .arcEnd(entityID):
            let arc = try arc(entityID, in: sketch)
            return try point(on: arc, at: arc.endAngle)
        case .arcRadius:
            throw SketchError.invalidReference("Arc radius is not a point reference.")
        case let .splineControlPoint(entityID, index):
            let spline = try spline(entityID, in: sketch)
            guard spline.controlPoints.indices.contains(index) else {
                throw SketchError.invalidReference("Spline control point reference points outside the spline.")
            }
            return try resolved(spline.controlPoints[index])
        }
    }

    private func angle(
        from first: SketchReference,
        to second: SketchReference,
        in sketch: Sketch,
        tolerance: ModelingTolerance
    ) throws -> Double {
        if let arcSpan = try arcSpanAngle(from: first, to: second, in: sketch) {
            return arcSpan
        }
        if case let .entity(firstID) = first,
           case let .entity(secondID) = second,
           isLine(firstID, in: sketch),
           isLine(secondID, in: sketch) {
            return try angleBetweenLines(firstID, secondID, in: sketch, tolerance: tolerance)
        }
        let firstPoint = try point(for: first, in: sketch)
        let secondPoint = try point(for: second, in: sketch)
        let dx = secondPoint.x - firstPoint.x
        let dy = secondPoint.y - firstPoint.y
        let length = hypot(dx, dy)
        guard length > tolerance.distance else {
            throw GeometryError.invalidVectorLength(length)
        }
        return atan2(dy, dx)
    }

    private func angleBetweenLines(
        _ firstID: SketchEntityID,
        _ secondID: SketchEntityID,
        in sketch: Sketch,
        tolerance: ModelingTolerance
    ) throws -> Double {
        let first = try direction(of: firstID, in: sketch, tolerance: tolerance)
        let second = try direction(of: secondID, in: sketch, tolerance: tolerance)
        let dot = min(max(first.x * second.x + first.y * second.y, -1.0), 1.0)
        return acos(dot)
    }

    private func arcSpanAngle(
        from first: SketchReference,
        to second: SketchReference,
        in sketch: Sketch
    ) throws -> Double? {
        switch (first, second) {
        case let (.arcStart(firstID), .arcEnd(secondID)) where firstID == secondID:
            let arc = try arc(firstID, in: sketch)
            let start = try angleValue(arc.startAngle, operation: "sketch.arc.startAngle")
            let end = try angleValue(arc.endAngle, operation: "sketch.arc.endAngle")
            return normalizedPositiveAngle(end - start)
        case let (.arcEnd(firstID), .arcStart(secondID)) where firstID == secondID:
            let arc = try arc(firstID, in: sketch)
            let start = try angleValue(arc.startAngle, operation: "sketch.arc.startAngle")
            let end = try angleValue(arc.endAngle, operation: "sketch.arc.endAngle")
            return normalizedPositiveAngle(start - end)
        default:
            return nil
        }
    }

    private func direction(
        of entityID: SketchEntityID,
        in sketch: Sketch,
        tolerance: ModelingTolerance
    ) throws -> Point2D {
        let line = try line(entityID, in: sketch)
        let start = try resolved(line.start)
        let end = try resolved(line.end)
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length > tolerance.distance else {
            throw GeometryError.invalidVectorLength(length)
        }
        return Point2D(x: dx / length, y: dy / length)
    }

    private func point(on arc: SketchArc, at angleExpression: CADExpression) throws -> Point2D {
        let center = try resolved(arc.center)
        let radius = try lengthValue(arc.radius, operation: "sketch.arc.radius")
        let angle = try angleValue(angleExpression, operation: "sketch.arc.angle")
        return Point2D(
            x: center.x + radius * cos(angle),
            y: center.y + radius * sin(angle)
        )
    }

    private func resolved(_ point: SketchPoint) throws -> Point2D {
        Point2D(
            x: try lengthValue(point.x, operation: "sketch.point.x"),
            y: try lengthValue(point.y, operation: "sketch.point.y")
        )
    }

    private func radius(of entityID: SketchEntityID, in sketch: Sketch) throws -> Double {
        guard let entity = sketch.entities[entityID] else {
            throw SketchError.invalidReference("Circular reference points to a missing entity.")
        }
        switch entity {
        case let .circle(circle):
            return try lengthValue(circle.radius, operation: "sketch.circle.radius")
        case let .arc(arc):
            return try lengthValue(arc.radius, operation: "sketch.arc.radius")
        case .point, .line, .spline:
            throw SketchError.invalidReference("Dimension radius reference must point to a circular entity.")
        }
    }

    private func line(_ entityID: SketchEntityID, in sketch: Sketch) throws -> SketchLine {
        guard let entity = sketch.entities[entityID],
              case let .line(line) = entity else {
            throw SketchError.invalidReference("Sketch reference must point to a line entity.")
        }
        return line
    }

    private func circle(_ entityID: SketchEntityID, in sketch: Sketch) throws -> SketchCircle {
        guard let entity = sketch.entities[entityID],
              case let .circle(circle) = entity else {
            throw SketchError.invalidReference("Sketch reference must point to a circle entity.")
        }
        return circle
    }

    private func arc(_ entityID: SketchEntityID, in sketch: Sketch) throws -> SketchArc {
        guard let entity = sketch.entities[entityID],
              case let .arc(arc) = entity else {
            throw SketchError.invalidReference("Sketch reference must point to an arc entity.")
        }
        return arc
    }

    private func spline(_ entityID: SketchEntityID, in sketch: Sketch) throws -> SketchSpline {
        guard let entity = sketch.entities[entityID],
              case let .spline(spline) = entity else {
            throw SketchError.invalidReference("Sketch reference must point to a spline entity.")
        }
        return spline
    }

    private func isLine(_ entityID: SketchEntityID, in sketch: Sketch) -> Bool {
        guard let entity = sketch.entities[entityID],
              case .line = entity else {
            return false
        }
        return true
    }

    private func lengthValue(_ expression: CADExpression, operation: String) throws -> Double {
        let quantity = try target(expression, expected: .length, operation: operation)
        return quantity.value
    }

    private func angleValue(_ expression: CADExpression, operation: String) throws -> Double {
        let quantity = try target(expression, expected: .angle, operation: operation)
        return quantity.value
    }

    private func distance(from first: Point2D, to second: Point2D) -> Double {
        hypot(second.x - first.x, second.y - first.y)
    }

    private func normalizedPositiveAngle(_ angle: Double) -> Double {
        let period = Double.pi * 2.0
        var result = angle.truncatingRemainder(dividingBy: period)
        if result < 0.0 {
            result += period
        }
        return result
    }

    private func normalizedSignedAngle(_ angle: Double) -> Double {
        let period = Double.pi * 2.0
        var result = angle.truncatingRemainder(dividingBy: period)
        if result > Double.pi {
            result -= period
        } else if result < -Double.pi {
            result += period
        }
        return result
    }
}
