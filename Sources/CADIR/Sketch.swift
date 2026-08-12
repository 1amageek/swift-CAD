import CADCore

public struct Sketch: Codable, Sendable, Hashable {
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

    private enum CodingKeys: String, CodingKey {
        case id
        case plane
        case entities
        case entityOrder
        case constraints
        case dimensions
    }

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
        try tolerance.validate()
        if case let .plane(plane) = plane {
            try plane.validate(tolerance: tolerance)
        }
        for entity in entities.values {
            try validateLiteralQuantities(in: entity)
        }
        for constraint in constraints {
            try validate(constraint)
        }
        for dimension in dimensions {
            try validate(dimension)
        }
    }

    public func validateExpressions(using parameters: ParameterTable) throws {
        for entity in entities.values {
            try validateExpressions(in: entity, using: parameters)
        }
        for dimension in dimensions {
            try validateExpression(in: dimension, using: parameters)
        }
    }

    private func validateExpressions(in entity: SketchEntity, using parameters: ParameterTable) throws {
        switch entity {
        case let .point(point):
            try resolveLengthExpression(point.x, operation: "sketch.x", using: parameters)
            try resolveLengthExpression(point.y, operation: "sketch.y", using: parameters)
        case let .line(line):
            try resolveLengthExpression(line.start.x, operation: "sketch.line.start.x", using: parameters)
            try resolveLengthExpression(line.start.y, operation: "sketch.line.start.y", using: parameters)
            try resolveLengthExpression(line.end.x, operation: "sketch.line.end.x", using: parameters)
            try resolveLengthExpression(line.end.y, operation: "sketch.line.end.y", using: parameters)
        case let .circle(circle):
            try resolveLengthExpression(circle.center.x, operation: "sketch.circle.center.x", using: parameters)
            try resolveLengthExpression(circle.center.y, operation: "sketch.circle.center.y", using: parameters)
            let radius = try resolveLengthExpression(
                circle.radius,
                operation: "sketch.circle.radius",
                using: parameters
            )
            guard radius.value > 0.0 else {
                throw GeometryError.invalidRadius(radius.value)
            }
        case let .arc(arc):
            try resolveLengthExpression(arc.center.x, operation: "sketch.arc.center.x", using: parameters)
            try resolveLengthExpression(arc.center.y, operation: "sketch.arc.center.y", using: parameters)
            let radius = try resolveLengthExpression(
                arc.radius,
                operation: "sketch.arc.radius",
                using: parameters
            )
            guard radius.value > 0.0 else {
                throw GeometryError.invalidRadius(radius.value)
            }
            try resolveAngleExpression(arc.startAngle, operation: "sketch.arc.startAngle", using: parameters)
            try resolveAngleExpression(arc.endAngle, operation: "sketch.arc.endAngle", using: parameters)
        case let .spline(spline):
            try validateSplineControlPointCount(spline)
            for (index, point) in spline.controlPoints.enumerated() {
                try resolveLengthExpression(
                    point.x,
                    operation: "sketch.spline.controlPoints[\(index)].x",
                    using: parameters
                )
                try resolveLengthExpression(
                    point.y,
                    operation: "sketch.spline.controlPoints[\(index)].y",
                    using: parameters
                )
            }
        }
    }

    private func validateExpression(in dimension: SketchDimension, using parameters: ParameterTable) throws {
        switch dimension {
        case let .distance(_, _, value):
            let distance = try resolveLengthExpression(value, operation: "sketch.dimension.distance", using: parameters)
            guard distance.value >= 0.0 else {
                throw GeometryError.invalidDistance(distance.value)
            }
        case let .angle(from, to, value):
            let angle = try resolveAngleExpression(value, operation: "sketch.dimension.angle", using: parameters)
            guard isArcSpanAngleDimension(from: from, to: to) == false || angle.value > 0.0 else {
                throw GeometryError.invalidAngle(angle.value)
            }
        case let .radius(_, value):
            let radius = try resolveLengthExpression(value, operation: "sketch.dimension.radius", using: parameters)
            guard radius.value > 0.0 else {
                throw GeometryError.invalidRadius(radius.value)
            }
        case let .diameter(_, value):
            let diameter = try resolveLengthExpression(value, operation: "sketch.dimension.diameter", using: parameters)
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
    ) throws -> Quantity {
        let quantity = try parameters.resolvedValue(for: expression)
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
    ) throws -> Quantity {
        let quantity = try parameters.resolvedValue(for: expression)
        guard quantity.kind == .angle else {
            throw UnitError.expectedQuantity(operation: operation, expected: .angle, actual: quantity.kind)
        }
        return quantity
    }

    private func validateLiteralQuantities(in entity: SketchEntity) throws {
        switch entity {
        case let .point(point):
            try point.x.validateLiteralQuantities()
            try point.y.validateLiteralQuantities()
        case let .line(line):
            try line.start.x.validateLiteralQuantities()
            try line.start.y.validateLiteralQuantities()
            try line.end.x.validateLiteralQuantities()
            try line.end.y.validateLiteralQuantities()
        case let .circle(circle):
            try circle.center.x.validateLiteralQuantities()
            try circle.center.y.validateLiteralQuantities()
            try circle.radius.validateLiteralQuantities()
        case let .arc(arc):
            try arc.center.x.validateLiteralQuantities()
            try arc.center.y.validateLiteralQuantities()
            try arc.radius.validateLiteralQuantities()
            try arc.startAngle.validateLiteralQuantities()
            try arc.endAngle.validateLiteralQuantities()
        case let .spline(spline):
            try validateSplineControlPointCount(spline)
            for point in spline.controlPoints {
                try point.x.validateLiteralQuantities()
                try point.y.validateLiteralQuantities()
            }
        }
    }

    private func validate(_ constraint: SketchConstraint) throws {
        switch constraint {
        case let .coincident(first, second):
            try validatePointReference(first)
            try validatePointReference(second)
        case let .horizontal(entityID), let .vertical(entityID):
            try validateLineEntity(entityID)
        case let .parallel(first, second),
             let .perpendicular(first, second),
             let .equalLength(first, second):
            try validateLineEntity(first)
            try validateLineEntity(second)
        case let .tangent(tangency):
            try validate(tangency)
        case let .concentric(first, second),
             let .equalRadius(first, second):
            try validateCircularEntity(first)
            try validateCircularEntity(second)
        case let .smoothSplineControlPoint(entityID, index):
            try validateSmoothSplineControlPointConstraint(entityID, index: index)
        case let .splineEndpointTangent(tangency):
            try validateSplineEndpointTangentConstraint(tangency)
        case let .tangentSplineEndpoints(tangency):
            try validateSplineEndpointsConstraint(tangency, operation: "Tangent")
        case let .smoothSplineEndpoints(tangency):
            try validateSplineEndpointsConstraint(tangency, operation: "Smooth")
        case let .fixed(reference):
            try validateReference(reference)
        }
    }

    private func validate(_ dimension: SketchDimension) throws {
        switch dimension {
        case let .distance(from, to, value):
            try validatePointReference(from)
            try validatePointReference(to)
            try value.validateLiteralQuantities()
        case let .angle(from, to, value):
            try validateReference(from)
            try validateReference(to)
            try value.validateLiteralQuantities()
        case let .radius(entityID, value), let .diameter(entityID, value):
            try validateCircularEntity(entityID)
            try value.validateLiteralQuantities()
        }
    }

    private func validateReference(_ reference: SketchReference) throws {
        switch reference {
        case let .entity(entityID):
            guard entities[entityID] != nil else {
                throw SketchError.invalidReference("Sketch reference points to a missing entity.")
            }
        case let .lineStart(entityID), let .lineEnd(entityID):
            try validateLineEntity(entityID)
        case let .circleCenter(entityID), let .circleRadius(entityID):
            try validateCircleEntity(entityID)
        case let .arcCenter(entityID),
             let .arcStart(entityID),
             let .arcEnd(entityID),
             let .arcRadius(entityID):
            try validateArcEntity(entityID)
        case let .splineControlPoint(entityID, index):
            try validateSplineControlPointReference(entityID, index: index)
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

    private func validatePointReference(_ reference: SketchReference) throws {
        switch reference {
        case let .entity(entityID):
            guard let entity = entities[entityID], case .point = entity else {
                throw SketchError.invalidReference("Entity reference must point to a sketch point.")
            }
        case let .lineStart(entityID), let .lineEnd(entityID):
            try validateLineEntity(entityID)
        case let .circleCenter(entityID):
            try validateCircleEntity(entityID)
        case .circleRadius:
            throw SketchError.invalidReference("Circle radius is not a point reference.")
        case let .arcCenter(entityID), let .arcStart(entityID), let .arcEnd(entityID):
            try validateArcEntity(entityID)
        case .arcRadius:
            throw SketchError.invalidReference("Arc radius is not a point reference.")
        case let .splineControlPoint(entityID, index):
            try validateSplineControlPointReference(entityID, index: index)
        }
    }

    private func validateLineEntity(_ entityID: SketchEntityID) throws {
        guard let entity = entities[entityID], case .line = entity else {
            throw SketchError.invalidReference("Sketch reference must point to a line entity.")
        }
    }

    private func validateCircleEntity(_ entityID: SketchEntityID) throws {
        guard let entity = entities[entityID], case .circle = entity else {
            throw SketchError.invalidReference("Sketch reference must point to a circle entity.")
        }
    }

    private func validateSplineControlPointReference(_ entityID: SketchEntityID, index: Int) throws {
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

    private func validateSmoothSplineControlPointConstraint(_ entityID: SketchEntityID, index: Int) throws {
        guard index >= 0 else {
            throw SketchError.invalidReference("Smooth spline control point index must not be negative.")
        }
        guard let entity = entities[entityID], case let .spline(spline) = entity else {
            throw SketchError.invalidReference("Smooth spline control point constraint requires a spline entity.")
        }
        try validateSplineControlPointCount(spline)
        guard spline.controlPoints.indices.contains(index) else {
            throw SketchError.invalidReference("Smooth spline control point constraint points outside the spline.")
        }
        guard index > 0, index < spline.controlPoints.count - 1, index.isMultiple(of: 3) else {
            throw SketchError.invalidReference(
                "Smooth spline control point constraint requires an internal cubic spline knot index."
            )
        }
    }

    private func validateSplineEndpointTangentConstraint(
        _ tangency: SketchSplineLineTangencyConstraint
    ) throws {
        try tangency.validate()
        let splineID = tangency.splineEndpoint.splineID
        let endpoint = tangency.splineEndpoint.endpoint
        guard let entity = entities[splineID], case let .spline(spline) = entity else {
            throw SketchError.invalidReference("Spline endpoint tangent constraint requires a spline entity.")
        }
        try validateSplineControlPointCount(spline)
        switch endpoint {
        case .start:
            try validateSplineControlPointReference(splineID, index: 0)
            try validateSplineControlPointReference(splineID, index: 1)
        case .end:
            try validateSplineControlPointReference(splineID, index: spline.controlPoints.count - 2)
            try validateSplineControlPointReference(splineID, index: spline.controlPoints.count - 1)
        }
        try validateLineEntity(tangency.line)
    }

    private func validateSplineEndpointsConstraint(
        _ tangency: SketchSplineEndpointTangencyConstraint,
        operation: String
    ) throws {
        try tangency.validate()
        try validateSplineEndpoint(tangency.first)
        try validateSplineEndpoint(tangency.second)
        guard tangency.first.splineID != tangency.second.splineID
                || tangency.first.endpoint != tangency.second.endpoint else {
            throw SketchError.invalidReference(
                "\(operation) spline endpoints constraint requires two distinct endpoints."
            )
        }
    }

    private func validateSplineEndpoint(_ reference: SketchSplineEndpointReference) throws {
        guard let entity = entities[reference.splineID], case let .spline(spline) = entity else {
            throw SketchError.invalidReference("Spline endpoint reference requires a spline entity.")
        }
        try validateSplineControlPointCount(spline)
        switch reference.endpoint {
        case .start:
            try validateSplineControlPointReference(reference.splineID, index: 0)
            try validateSplineControlPointReference(reference.splineID, index: 1)
        case .end:
            try validateSplineControlPointReference(reference.splineID, index: spline.controlPoints.count - 2)
            try validateSplineControlPointReference(reference.splineID, index: spline.controlPoints.count - 1)
        }
    }

    private func validate(_ tangency: SketchTangencyConstraint) throws {
        try tangency.validate()
        switch tangency {
        case let .lineCircular(line, circular, _):
            try validateLineEntity(line)
            try validateCircularEntity(circular)
        case let .circularCircular(first, second, _):
            try validateCircularEntity(first)
            try validateCircularEntity(second)
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

    private func validateArcEntity(_ entityID: SketchEntityID) throws {
        guard let entity = entities[entityID], case .arc = entity else {
            throw SketchError.invalidReference("Sketch reference must point to an arc entity.")
        }
    }

    private func validateCircularEntity(_ entityID: SketchEntityID) throws {
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

    private func validateSplineControlPointCount(_ spline: SketchSpline) throws {
        let count = spline.controlPoints.count
        guard count >= 4, (count - 1).isMultiple(of: 3) else {
            throw SketchError.unsupportedEntity(
                "Cubic sketch spline control point count must be 3n + 1 and at least 4."
            )
        }
    }
}
