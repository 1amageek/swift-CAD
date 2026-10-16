import CADGeometry
import CADCore

public struct Sketch: Sendable, Hashable {
    public var id: SketchID
    public var plane: SketchPlane
    public var entities: [SketchEntityID: SketchEntity]
    // Authoring order of entities. Consumers that enumerate entities as an
    // ordered output (curve extraction, profile chaining) follow this order
    // so indices are reproducible across process runs; entity IDs are
    // random per construction, so any ID-derived order reshuffles between
    // runs of the same building code.
    public var entityOrder: [SketchEntityID]
    public var constraints: [SketchConstraint]
    public var dimensions: [SketchDimension]

    public init(
        id: SketchID = SketchID(),
        plane: SketchPlane,
        entities: [SketchEntityID: SketchEntity] = [:],
        entityOrder: [SketchEntityID] = [],
        constraints: [SketchConstraint] = [],
        dimensions: [SketchDimension] = []
    ) {
        self.id = id
        self.plane = plane
        self.entities = entities
        self.entityOrder = entityOrder
        self.constraints = constraints
        self.dimensions = dimensions
    }

#if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey {
        case id
        case plane
        case entities
        case entityOrder
        case constraints
        case dimensions
    }
#endif

#if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(SketchID.self, forKey: .id)
        plane = try container.decode(SketchPlane.self, forKey: .plane)
        entities = try container.decode(
            [SketchEntityID: SketchEntity].self,
            forKey: .entities
        )
        // Documents written before authoring order existed fall back to the
        // stable ID-derived order their persisted IDs already define.
        entityOrder = try container.decodeIfPresent(
            [SketchEntityID].self,
            forKey: .entityOrder
        ) ?? []
        constraints = try container.decode(
            [SketchConstraint].self,
            forKey: .constraints
        )
        dimensions = try container.decode(
            [SketchDimension].self,
            forKey: .dimensions
        )
    }
#endif

    /// Entities in authoring order, followed by any entities missing from
    /// the order list in their stable ID-derived order.
    public var orderedEntities: [(id: SketchEntityID, entity: SketchEntity)] {
        var seen: Set<SketchEntityID> = []
        var result: [(id: SketchEntityID, entity: SketchEntity)] = []
        for entityID in entityOrder {
            guard seen.insert(entityID).inserted,
                  let entity = entities[entityID] else {
                continue
            }
            result.append((id: entityID, entity: entity))
        }
        for entityID in entities.keys.sorted(by: {
            $0.description < $1.description
        }) where seen.contains(entityID) == false {
            result.append((id: entityID, entity: entities[entityID]!))
        }
        return result
    }

    public func validate(tolerance: ModelingTolerance) throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try validate(tolerance: tolerance, using: &execution)
    }

    public func validate(tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        try tolerance.validate()
        if case let .plane(plane) = plane {
            try plane.validate(tolerance: tolerance)
        }
        for entity in entities.values {
            try execution.consumeWork(1)
            try validateLiteralQuantities(in: entity, execution: &execution)
        }
        for constraint in constraints {
            try execution.consumeWork(1)
            try validate(constraint, execution: &execution)
        }
        for dimension in dimensions {
            try execution.consumeWork(1)
            try validate(dimension, execution: &execution)
        }
    }

    public func validateExpressions(using parameters: ParameterTable) throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try validateExpressions(using: parameters, execution: &execution)
    }

    public func validateExpressions(using parameters: ParameterTable, execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        for entity in entities.values {
            try execution.consumeWork(1)
            try validateExpressions(in: entity, using: parameters, execution: &execution)
        }
        for dimension in dimensions {
            try execution.consumeWork(1)
            try validateExpression(in: dimension, using: parameters, execution: &execution)
        }
    }

    private func validateExpressions(in entity: SketchEntity, using parameters: ParameterTable, execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        switch entity {
        case let .point(point):
            try resolveLengthExpression(point.x, operation: "sketch.x", using: parameters, execution: &execution)
            try resolveLengthExpression(point.y, operation: "sketch.y", using: parameters, execution: &execution)
        case let .line(line):
            try resolveLengthExpression(line.start.x, operation: "sketch.line.start.x", using: parameters, execution: &execution)
            try resolveLengthExpression(line.start.y, operation: "sketch.line.start.y", using: parameters, execution: &execution)
            try resolveLengthExpression(line.end.x, operation: "sketch.line.end.x", using: parameters, execution: &execution)
            try resolveLengthExpression(line.end.y, operation: "sketch.line.end.y", using: parameters, execution: &execution)
        case let .circle(circle):
            try resolveLengthExpression(circle.center.x, operation: "sketch.circle.center.x", using: parameters, execution: &execution)
            try resolveLengthExpression(circle.center.y, operation: "sketch.circle.center.y", using: parameters, execution: &execution)
            let radius = try resolveLengthExpression(
                circle.radius,
                operation: "sketch.circle.radius",
                using: parameters
            , execution: &execution)
            guard radius.value > 0.0 else {
                throw GeometryError.invalidRadius(radius.value)
            }
        case let .arc(arc):
            try resolveLengthExpression(arc.center.x, operation: "sketch.arc.center.x", using: parameters, execution: &execution)
            try resolveLengthExpression(arc.center.y, operation: "sketch.arc.center.y", using: parameters, execution: &execution)
            let radius = try resolveLengthExpression(
                arc.radius,
                operation: "sketch.arc.radius",
                using: parameters
            , execution: &execution)
            guard radius.value > 0.0 else {
                throw GeometryError.invalidRadius(radius.value)
            }
            try resolveAngleExpression(arc.startAngle, operation: "sketch.arc.startAngle", using: parameters, execution: &execution)
            try resolveAngleExpression(arc.endAngle, operation: "sketch.arc.endAngle", using: parameters, execution: &execution)
        case let .spline(spline):
            try validateSplineControlPointCount(spline, execution: &execution)
            for (index, point) in spline.controlPoints.enumerated() {
            try execution.consumeWork(1)
                try resolveLengthExpression(
                    point.x,
                    operation: "sketch.spline.controlPoints[\(index)].x",
                    using: parameters
                , execution: &execution)
                try resolveLengthExpression(
                    point.y,
                    operation: "sketch.spline.controlPoints[\(index)].y",
                    using: parameters
                , execution: &execution)
            }
        }
    }

    private func validateExpression(in dimension: SketchDimension, using parameters: ParameterTable, execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        switch dimension {
        case let .distance(_, _, value):
            let distance = try resolveLengthExpression(value, operation: "sketch.dimension.distance", using: parameters, execution: &execution)
            guard distance.value >= 0.0 else {
                throw GeometryError.invalidDistance(distance.value)
            }
        case let .angle(from, to, value):
            let angle = try resolveAngleExpression(value, operation: "sketch.dimension.angle", using: parameters, execution: &execution)
            guard isArcSpanAngleDimension(from: from, to: to) == false || angle.value > 0.0 else {
                throw GeometryError.invalidAngle(angle.value)
            }
        case let .radius(_, value):
            let radius = try resolveLengthExpression(value, operation: "sketch.dimension.radius", using: parameters, execution: &execution)
            guard radius.value > 0.0 else {
                throw GeometryError.invalidRadius(radius.value)
            }
        case let .diameter(_, value):
            let diameter = try resolveLengthExpression(value, operation: "sketch.dimension.diameter", using: parameters, execution: &execution)
            guard diameter.value > 0.0 else {
                throw GeometryError.invalidDistance(diameter.value)
            }
        }
    }

    @discardableResult
    private func resolveLengthExpression(
        _ expression: CADExpression,
        operation: String,
        using parameters: ParameterTable
    , execution: inout OriginalQueryExecution) throws -> Quantity {
        try execution.consumeWork(1)
        let quantity = try parameters.resolvedValue(for: expression, using: &execution)
        guard quantity.kind == .length else {
            throw UnitError.expectedQuantity(operation: operation, expected: .length, actual: quantity.kind)
        }
        return quantity
    }

    @discardableResult
    private func resolveAngleExpression(
        _ expression: CADExpression,
        operation: String,
        using parameters: ParameterTable
    , execution: inout OriginalQueryExecution) throws -> Quantity {
        try execution.consumeWork(1)
        let quantity = try parameters.resolvedValue(for: expression, using: &execution)
        guard quantity.kind == .angle else {
            throw UnitError.expectedQuantity(operation: operation, expected: .angle, actual: quantity.kind)
        }
        return quantity
    }

    private func validateLiteralQuantities(in entity: SketchEntity, execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        switch entity {
        case let .point(point):
            try point.x.validateDocumentLiteralQuantities(using: &execution)
            try point.y.validateDocumentLiteralQuantities(using: &execution)
        case let .line(line):
            try line.start.x.validateDocumentLiteralQuantities(using: &execution)
            try line.start.y.validateDocumentLiteralQuantities(using: &execution)
            try line.end.x.validateDocumentLiteralQuantities(using: &execution)
            try line.end.y.validateDocumentLiteralQuantities(using: &execution)
        case let .circle(circle):
            try circle.center.x.validateDocumentLiteralQuantities(using: &execution)
            try circle.center.y.validateDocumentLiteralQuantities(using: &execution)
            try circle.radius.validateDocumentLiteralQuantities(using: &execution)
        case let .arc(arc):
            try arc.center.x.validateDocumentLiteralQuantities(using: &execution)
            try arc.center.y.validateDocumentLiteralQuantities(using: &execution)
            try arc.radius.validateDocumentLiteralQuantities(using: &execution)
            try arc.startAngle.validateDocumentLiteralQuantities(using: &execution)
            try arc.endAngle.validateDocumentLiteralQuantities(using: &execution)
        case let .spline(spline):
            try validateSplineControlPointCount(spline, execution: &execution)
            for point in spline.controlPoints {
            try execution.consumeWork(1)
                try point.x.validateDocumentLiteralQuantities(using: &execution)
                try point.y.validateDocumentLiteralQuantities(using: &execution)
            }
        }
    }

    private func validate(_ constraint: SketchConstraint, execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        switch constraint {
        case let .coincident(first, second):
            try validatePointReference(first, execution: &execution)
            try validatePointReference(second, execution: &execution)
        case let .horizontal(entityID), let .vertical(entityID):
            try validateLineEntity(entityID, execution: &execution)
        case let .parallel(first, second),
             let .perpendicular(first, second),
             let .equalLength(first, second):
            try validateLineEntity(first, execution: &execution)
            try validateLineEntity(second, execution: &execution)
        case let .tangent(tangency):
            try validate(tangency, execution: &execution)
        case let .concentric(first, second),
             let .equalRadius(first, second):
            try validateCircularEntity(first, execution: &execution)
            try validateCircularEntity(second, execution: &execution)
        case let .smoothSplineControlPoint(entityID, index):
            try validateSmoothSplineControlPointConstraint(entityID, index: index, execution: &execution)
        case let .splineEndpointTangent(tangency):
            try validateSplineEndpointTangentConstraint(tangency, execution: &execution)
        case let .tangentSplineEndpoints(tangency):
            try validateSplineEndpointsConstraint(tangency, operation: "Tangent", execution: &execution)
        case let .smoothSplineEndpoints(tangency):
            try validateSplineEndpointsConstraint(tangency, operation: "Smooth", execution: &execution)
        case let .fixed(reference):
            try validateReference(reference, execution: &execution)
        }
    }

    private func validate(_ dimension: SketchDimension, execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        switch dimension {
        case let .distance(from, to, value):
            try validatePointReference(from, execution: &execution)
            try validatePointReference(to, execution: &execution)
            try value.validateDocumentLiteralQuantities(using: &execution)
        case let .angle(from, to, value):
            try validateReference(from, execution: &execution)
            try validateReference(to, execution: &execution)
            try value.validateDocumentLiteralQuantities(using: &execution)
        case let .radius(entityID, value), let .diameter(entityID, value):
            try validateCircularEntity(entityID, execution: &execution)
            try value.validateDocumentLiteralQuantities(using: &execution)
        }
    }

    private func validateReference(_ reference: SketchReference, execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        switch reference {
        case let .entity(entityID):
            guard entities[entityID] != nil else {
                throw SketchError.invalidReference("Sketch reference points to a missing entity.")
            }
        case let .lineStart(entityID), let .lineEnd(entityID):
            try validateLineEntity(entityID, execution: &execution)
        case let .circleCenter(entityID), let .circleRadius(entityID):
            try validateCircleEntity(entityID, execution: &execution)
        case let .arcCenter(entityID),
             let .arcStart(entityID),
             let .arcEnd(entityID),
             let .arcRadius(entityID):
            try validateArcEntity(entityID, execution: &execution)
        case let .splineControlPoint(entityID, index):
            try validateSplineControlPointReference(entityID, index: index, execution: &execution)
        }
    }

    private func isArcSpanAngleDimension(from: SketchReference, to: SketchReference) -> Bool {
        switch (from, to) {
        case (.arcStart(let firstID), .arcEnd(let secondID)),
             (.arcEnd(let firstID), .arcStart(let secondID)):
            return firstID == secondID
        default:
            return false
        }
    }

    private func validatePointReference(_ reference: SketchReference, execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        switch reference {
        case let .entity(entityID):
            guard let entity = entities[entityID], case .point = entity else {
                throw SketchError.invalidReference("Entity reference must point to a sketch point.")
            }
        case let .lineStart(entityID), let .lineEnd(entityID):
            try validateLineEntity(entityID, execution: &execution)
        case let .circleCenter(entityID):
            try validateCircleEntity(entityID, execution: &execution)
        case .circleRadius:
            throw SketchError.invalidReference("Circle radius is not a point reference.")
        case let .arcCenter(entityID), let .arcStart(entityID), let .arcEnd(entityID):
            try validateArcEntity(entityID, execution: &execution)
        case .arcRadius:
            throw SketchError.invalidReference("Arc radius is not a point reference.")
        case let .splineControlPoint(entityID, index):
            try validateSplineControlPointReference(entityID, index: index, execution: &execution)
        }
    }

    private func validateLineEntity(_ entityID: SketchEntityID, execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        guard let entity = entities[entityID], case .line = entity else {
            throw SketchError.invalidReference("Sketch reference must point to a line entity.")
        }
    }

    private func validateCircleEntity(_ entityID: SketchEntityID, execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        guard let entity = entities[entityID], case .circle = entity else {
            throw SketchError.invalidReference("Sketch reference must point to a circle entity.")
        }
    }

    private func validateSplineControlPointReference(_ entityID: SketchEntityID, index: Int, execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        guard index >= 0 else {
            throw SketchError.invalidReference("Spline control point reference index must not be negative.")
        }
        guard let entity = entities[entityID], case let .spline(spline) = entity else {
            throw SketchError.invalidReference("Sketch reference must point to a spline entity.")
        }
        guard spline.controlPoints.indices.contains(index) else {
            throw SketchError.invalidReference("Spline control point reference points outside the spline.")
        }
    }

    private func validateSmoothSplineControlPointConstraint(_ entityID: SketchEntityID, index: Int, execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        guard index >= 0 else {
            throw SketchError.invalidReference("Smooth spline control point index must not be negative.")
        }
        guard let entity = entities[entityID], case let .spline(spline) = entity else {
            throw SketchError.invalidReference("Smooth spline control point constraint requires a spline entity.")
        }
        try validateSplineControlPointCount(spline, execution: &execution)
        guard spline.controlPoints.indices.contains(index) else {
            throw SketchError.invalidReference("Smooth spline control point constraint points outside the spline.")
        }
        guard spline.isBezierChain, index > 0, index < spline.controlPoints.count - 1,
              index.isMultiple(of: spline.degree) else {
            throw SketchError.invalidReference(
                "Smooth spline control point constraint requires an internal joint index of a spline in chain form."
            )
        }
    }

    private func validateSplineEndpointTangentConstraint(
        _ tangency: SketchSplineLineTangencyConstraint
    , execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        try tangency.validate()
        let splineID = tangency.splineEndpoint.splineID
        let endpoint = tangency.splineEndpoint.endpoint
        guard let entity = entities[splineID], case let .spline(spline) = entity else {
            throw SketchError.invalidReference("Spline endpoint tangent constraint requires a spline entity.")
        }
        try validateSplineControlPointCount(spline, execution: &execution)
        switch endpoint {
        case .start:
            try validateSplineControlPointReference(splineID, index: 0, execution: &execution)
            try validateSplineControlPointReference(splineID, index: 1, execution: &execution)
        case .end:
            try validateSplineControlPointReference(splineID, index: spline.controlPoints.count - 2, execution: &execution)
            try validateSplineControlPointReference(splineID, index: spline.controlPoints.count - 1, execution: &execution)
        }
        try validateLineEntity(tangency.line, execution: &execution)
    }

    private func validateSplineEndpointsConstraint(
        _ tangency: SketchSplineEndpointTangencyConstraint,
        operation: String
    , execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        try tangency.validate()
        try validateSplineEndpoint(tangency.first, execution: &execution)
        try validateSplineEndpoint(tangency.second, execution: &execution)
        guard tangency.first.splineID != tangency.second.splineID
                || tangency.first.endpoint != tangency.second.endpoint else {
            throw SketchError.invalidReference(
                "\(operation) spline endpoints constraint requires two distinct endpoints."
            )
        }
    }

    private func validateSplineEndpoint(_ reference: SketchSplineEndpointReference, execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        guard let entity = entities[reference.splineID], case let .spline(spline) = entity else {
            throw SketchError.invalidReference("Spline endpoint reference requires a spline entity.")
        }
        try validateSplineControlPointCount(spline, execution: &execution)
        switch reference.endpoint {
        case .start:
            try validateSplineControlPointReference(reference.splineID, index: 0, execution: &execution)
            try validateSplineControlPointReference(reference.splineID, index: 1, execution: &execution)
        case .end:
            try validateSplineControlPointReference(reference.splineID, index: spline.controlPoints.count - 2, execution: &execution)
            try validateSplineControlPointReference(reference.splineID, index: spline.controlPoints.count - 1, execution: &execution)
        }
    }

    private func validate(_ tangency: SketchTangencyConstraint, execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        try tangency.validate()
        switch tangency {
        case let .lineCircular(line, circular, _):
            try validateLineEntity(line, execution: &execution)
            try validateCircularEntity(circular, execution: &execution)
        case let .circularCircular(first, second, _):
            try validateCircularEntity(first, execution: &execution)
            try validateCircularEntity(second, execution: &execution)
        }
    }

    private func isLineEntity(_ entityID: SketchEntityID) -> Bool {
        guard let entity = entities[entityID], case .line = entity else {
            return false
        }
        return true
    }

    private func isCircularEntity(_ entityID: SketchEntityID) -> Bool {
        guard let entity = entities[entityID] else {
            return false
        }
        switch entity {
        case .circle, .arc:
            return true
        case .point, .line, .spline:
            return false
        }
    }

    private func validateArcEntity(_ entityID: SketchEntityID, execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        guard let entity = entities[entityID], case .arc = entity else {
            throw SketchError.invalidReference("Sketch reference must point to an arc entity.")
        }
    }

    private func validateCircularEntity(_ entityID: SketchEntityID, execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        guard let entity = entities[entityID] else {
            throw SketchError.invalidReference("Sketch reference must point to a circular entity.")
        }
        switch entity {
        case .circle, .arc:
            return
        case .point, .line, .spline:
            throw SketchError.invalidReference("Sketch reference must point to a circular entity.")
        }
    }

    private func validateSplineControlPointCount(_ spline: SketchSpline, execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        try spline.validateForm(using: &execution)
    }
}

#if !hasFeature(Embedded)
extension Sketch: Codable {}
#endif
