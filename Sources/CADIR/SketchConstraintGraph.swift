import CADCore

public struct SketchConstraintGraph: Sendable, Equatable {
    public var nodes: Set<SketchConstraintNode>
    public var equations: [SketchConstraintEquation]

    public init(nodes: Set<SketchConstraintNode>, equations: [SketchConstraintEquation]) {
        self.nodes = nodes
        self.equations = equations
    }

    public func validate() throws {
        guard !nodes.isEmpty || equations.isEmpty else {
            throw SketchError.invalidReference("Sketch constraint graph has equations but no nodes.")
        }
        for equation in equations {
            guard !equation.nodes.isEmpty else {
                throw SketchError.invalidReference("Sketch constraint equation has no nodes.")
            }
            for node in equation.nodes {
                guard nodes.contains(node) else {
                    throw SketchError.invalidReference("Sketch constraint equation references a missing graph node.")
                }
            }
        }
    }
}

public struct SketchConstraintNode: Sendable, Codable, Hashable {
    public var reference: SketchReference
    public var degreeOfFreedom: SketchDegreeOfFreedom

    public init(reference: SketchReference, degreeOfFreedom: SketchDegreeOfFreedom) {
        self.reference = reference
        self.degreeOfFreedom = degreeOfFreedom
    }
}

public enum SketchDegreeOfFreedom: String, Codable, Sendable, Hashable {
    case x
    case y
    case radius
    case angle
    case length
}

public struct SketchConstraintEquation: Sendable, Codable, Hashable {
    public var kind: SketchConstraintEquationKind
    public var nodes: [SketchConstraintNode]

    public init(kind: SketchConstraintEquationKind, nodes: [SketchConstraintNode]) {
        self.kind = kind
        self.nodes = nodes
    }
}

public enum SketchConstraintEquationKind: String, Codable, Sendable, Hashable {
    case coincident
    case horizontal
    case vertical
    case parallel
    case perpendicular
    case equalLength
    case tangent
    case concentric
    case equalRadius
    case smoothSplineControlPoint
    case splineEndpointTangent
    case tangentSplineEndpoints
    case smoothSplineEndpoints
    case fixed
    case distance
    case angle
    case radius
    case diameter
}

public extension Sketch {
    func constraintGraph() throws -> SketchConstraintGraph {
        try validate()
        var nodes = Set<SketchConstraintNode>()
        var equations: [SketchConstraintEquation] = []

        func pointNodes(for reference: SketchReference) -> [SketchConstraintNode] {
            [
                SketchConstraintNode(reference: reference, degreeOfFreedom: .x),
                SketchConstraintNode(reference: reference, degreeOfFreedom: .y)
            ]
        }

        func lineAngleNode(for entityID: SketchEntityID) -> SketchConstraintNode {
            SketchConstraintNode(reference: .entity(entityID), degreeOfFreedom: .angle)
        }

        func lineLengthNode(for entityID: SketchEntityID) -> SketchConstraintNode {
            SketchConstraintNode(reference: .entity(entityID), degreeOfFreedom: .length)
        }

        func circleRadiusNode(for entityID: SketchEntityID) -> SketchConstraintNode {
            SketchConstraintNode(reference: .circleRadius(entityID), degreeOfFreedom: .radius)
        }

        func circularRadiusNode(for entityID: SketchEntityID) -> SketchConstraintNode {
            guard let entity = entities[entityID], case .arc = entity else {
                return circleRadiusNode(for: entityID)
            }
            return SketchConstraintNode(reference: .arcRadius(entityID), degreeOfFreedom: .radius)
        }

        func angularNode(for reference: SketchReference) -> SketchConstraintNode {
            SketchConstraintNode(reference: reference, degreeOfFreedom: .angle)
        }

        func circularCenterNodes(for entityID: SketchEntityID) -> [SketchConstraintNode] {
            guard let entity = entities[entityID], case .arc = entity else {
                return pointNodes(for: .circleCenter(entityID))
            }
            return pointNodes(for: .arcCenter(entityID))
        }

        func tangentNodes(first: SketchEntityID, second: SketchEntityID) throws -> [SketchConstraintNode] {
            if let firstEntity = entities[first], case .line = firstEntity {
                return [lineAngleNode(for: first)] + circularCenterNodes(for: second) + [circularRadiusNode(for: second)]
            }
            if let secondEntity = entities[second], case .line = secondEntity {
                return [lineAngleNode(for: second)] + circularCenterNodes(for: first) + [circularRadiusNode(for: first)]
            }
            throw SketchError.invalidReference("Tangent constraint requires one line entity.")
        }

        func smoothSplineControlPointNodes(
            entityID: SketchEntityID,
            index: Int
        ) -> [SketchConstraintNode] {
            pointNodes(for: .splineControlPoint(entity: entityID, index: index - 1)) +
                pointNodes(for: .splineControlPoint(entity: entityID, index: index)) +
                pointNodes(for: .splineControlPoint(entity: entityID, index: index + 1))
        }

        func splineEndpointTangentNodes(
            splineID: SketchEntityID,
            endpoint: SketchSplineEndpoint,
            lineID: SketchEntityID
        ) throws -> [SketchConstraintNode] {
            guard let entity = entities[splineID],
                  case let .spline(spline) = entity,
                  spline.controlPoints.count >= 4 else {
                throw SketchError.invalidReference("Spline endpoint tangent constraint requires a spline entity.")
            }
            let handleIndex: Int
            let endpointIndex: Int
            switch endpoint {
            case .start:
                endpointIndex = 0
                handleIndex = 1
            case .end:
                endpointIndex = spline.controlPoints.count - 1
                handleIndex = spline.controlPoints.count - 2
            }
            return pointNodes(for: .splineControlPoint(entity: splineID, index: endpointIndex)) +
                pointNodes(for: .splineControlPoint(entity: splineID, index: handleIndex)) +
                [lineAngleNode(for: lineID)]
        }

        func tangentSplineEndpointNodes(
            for reference: SketchSplineEndpointReference
        ) throws -> [SketchConstraintNode] {
            guard let entity = entities[reference.splineID],
                  case let .spline(spline) = entity,
                  spline.controlPoints.count >= 4 else {
                throw SketchError.invalidReference("Tangent spline endpoints constraint requires a spline entity.")
            }
            let endpointIndex: Int
            let handleIndex: Int
            switch reference.endpoint {
            case .start:
                endpointIndex = 0
                handleIndex = 1
            case .end:
                endpointIndex = spline.controlPoints.count - 1
                handleIndex = spline.controlPoints.count - 2
            }
            return pointNodes(for: .splineControlPoint(entity: reference.splineID, index: endpointIndex)) +
                pointNodes(for: .splineControlPoint(entity: reference.splineID, index: handleIndex))
        }

        func append(_ kind: SketchConstraintEquationKind, _ equationNodes: [SketchConstraintNode]) {
            for node in equationNodes {
                nodes.insert(node)
            }
            equations.append(SketchConstraintEquation(kind: kind, nodes: equationNodes))
        }

        for constraint in constraints {
            switch constraint {
            case let .coincident(first, second):
                append(.coincident, pointNodes(for: first) + pointNodes(for: second))
            case let .horizontal(entityID):
                append(.horizontal, [lineAngleNode(for: entityID)])
            case let .vertical(entityID):
                append(.vertical, [lineAngleNode(for: entityID)])
            case let .parallel(first, second):
                append(.parallel, [lineAngleNode(for: first), lineAngleNode(for: second)])
            case let .perpendicular(first, second):
                append(.perpendicular, [lineAngleNode(for: first), lineAngleNode(for: second)])
            case let .equalLength(first, second):
                append(.equalLength, [lineLengthNode(for: first), lineLengthNode(for: second)])
            case let .tangent(first, second):
                append(.tangent, try tangentNodes(first: first, second: second))
            case let .concentric(first, second):
                append(.concentric, circularCenterNodes(for: first) + circularCenterNodes(for: second))
            case let .equalRadius(first, second):
                append(.equalRadius, [circularRadiusNode(for: first), circularRadiusNode(for: second)])
            case let .smoothSplineControlPoint(entityID, index):
                append(
                    .smoothSplineControlPoint,
                    smoothSplineControlPointNodes(entityID: entityID, index: index)
                )
            case let .splineEndpointTangent(splineID, endpoint, lineID):
                append(
                    .splineEndpointTangent,
                    try splineEndpointTangentNodes(splineID: splineID, endpoint: endpoint, lineID: lineID)
                )
            case let .tangentSplineEndpoints(first, second):
                append(
                    .tangentSplineEndpoints,
                    try tangentSplineEndpointNodes(for: first) + tangentSplineEndpointNodes(for: second)
                )
            case let .smoothSplineEndpoints(first, second):
                append(
                    .smoothSplineEndpoints,
                    try tangentSplineEndpointNodes(for: first) + tangentSplineEndpointNodes(for: second)
                )
            case let .fixed(reference):
                append(.fixed, degreesOfFreedom(for: reference))
            }
        }

        for dimension in dimensions {
            switch dimension {
            case let .distance(from, to, _):
                append(.distance, pointNodes(for: from) + pointNodes(for: to))
            case let .angle(from, to, _):
                append(.angle, [angularNode(for: from), angularNode(for: to)])
            case let .radius(entityID, _):
                append(.radius, [circularRadiusNode(for: entityID)])
            case let .diameter(entityID, _):
                append(.diameter, [circularRadiusNode(for: entityID)])
            }
        }

        let graph = SketchConstraintGraph(nodes: nodes, equations: equations)
        try graph.validate()
        return graph
    }

    private func degreesOfFreedom(for reference: SketchReference) -> [SketchConstraintNode] {
        switch reference {
        case .entity,
             .lineStart,
             .lineEnd,
             .circleCenter,
             .arcCenter,
             .arcStart,
             .arcEnd,
             .splineControlPoint:
            [
                SketchConstraintNode(reference: reference, degreeOfFreedom: .x),
                SketchConstraintNode(reference: reference, degreeOfFreedom: .y)
            ]
        case .circleRadius, .arcRadius:
            [
                SketchConstraintNode(reference: reference, degreeOfFreedom: .radius)
            ]
        }
    }
}
