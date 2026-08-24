import CADCore
import CADGeometry
import CADIR
import CADTopology

public struct VertexMoveFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    private let resolver: ParameterResolving
    private let subshapeResolver: any StableSubshapeResolving
    private let sewer: any BRepSewing

    public init(
        sewer: any BRepSewing,
        resolver: ParameterResolving = ParameterResolver(),
        subshapeResolver: any StableSubshapeResolving = StableSubshapeResolver()
    ) {
        self.resolver = resolver
        self.subshapeResolver = subshapeResolver
        self.sewer = sewer
    }

    public func evaluate(
        feature: FeatureNode,
        context: EvaluationContext
    ) throws -> EvaluationResult {
        try evaluateValidated(feature: feature, context: context).result
    }

    package func evaluateValidated(
        feature: FeatureNode,
        context: EvaluationContext
    ) throws -> ValidatedFeatureEvaluation {
        try FeatureEvaluationBoundary.evaluateValidated(
            featureID: feature.id,
            tolerance: context.tolerance
        ) {
            try evaluateVertexMove(feature: feature, context: context)
        }
    }

    private func evaluateVertexMove(feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult {
        guard case let .vertexMove(move) = feature.operation else {
            throw error(.invalidInput, featureID: feature.id, tolerance: context.tolerance, "Vertex move evaluator requires a vertexMove feature.")
        }
        try FeatureEvaluationBoundary.validateRequest(featureID: feature.id, tolerance: context.tolerance) {
            try move.validate(tolerance: context.tolerance)
        }
        try FeatureEvaluationBoundary.validateExactInput(
            context,
            featureID: feature.id,
            tolerance: context.tolerance
        )
        let distance = try resolvedDistance(move.translation.distance, featureID: feature.id, context: context)
        let direction = try move.translation.direction.normalized(tolerance: context.tolerance.distance)
        let bodyID = try targetBodyID(move.target.featureID, featureID: feature.id, context: context)
        let bodyScope = try BodyTopologyScope(
            bodyID: bodyID,
            model: context.brep
        )
        let vertexID = try targetVertexID(
            move.vertex,
            bodyScope: bodyScope,
            featureID: feature.id,
            context: context
        )
        let replacedSubshapeIDs = bodyScope.subshapeIDs(in: context.subshapes)
        let request = try sewingRequest(
            featureID: feature.id,
            bodyID: bodyID,
            movedVertexID: vertexID,
            displacement: direction * distance,
            context: context
        )
        let sewn = try sewer.sew(request, tolerance: context.tolerance)
        var replacement = sewn.brep
        if var body = replacement.bodies[sewn.bodyID], let sourceBody = context.brep.bodies[bodyID] {
            body.name = sourceBody.name
            body.material = sourceBody.material
            replacement.bodies[sewn.bodyID] = body
        }
        let model = try BRepBodyModelReplacer().replacing(
            bodyIDs: [bodyID],
            with: replacement,
            in: context.brep
        )
        try model.validate(level: .volumetric, tolerance: context.tolerance)
        return EvaluationResult(
            brep: model,
            subshapes: sewn.subshapes,
            removedSubshapeIDs: replacedSubshapeIDs,
            lineage: sewn.lineage
        )
    }

    private func resolvedDistance(
        _ expression: CADExpression,
        featureID: FeatureID,
        context: EvaluationContext
    ) throws -> Double {
        let quantity = try resolver.evaluate(expression, parameters: context.parameters, variables: [:])
        guard quantity.kind == .length else {
            throw UnitError.expectedQuantity(operation: "vertexMove.distance", expected: .length, actual: quantity.kind)
        }
        guard quantity.value.isFinite,
              abs(quantity.value) > context.tolerance.distance else {
            throw error(.invalidInput, featureID: featureID, tolerance: context.tolerance, "Vertex move distance must be finite and larger than modeling tolerance.")
        }
        return quantity.value
    }

    private func targetBodyID(
        _ sourceFeatureID: FeatureID,
        featureID: FeatureID,
        context: EvaluationContext
    ) throws -> BodyID {
        try context.bodyID(generatedBy: sourceFeatureID)
    }

    private func targetVertexID(
        _ stableReference: StableSubshapeReference,
        bodyScope: BodyTopologyScope,
        featureID: FeatureID,
        context: EvaluationContext
    ) throws -> VertexID {
        let reference = try subshapeResolver.topologyReference(
            for: stableReference,
            model: context.brep,
            subshapes: context.subshapes,
            lineage: context.lineage,
            tolerance: context.tolerance
        )
        guard case let .vertex(vertexID) = reference else {
            throw error(
                .missingReference,
                featureID: featureID,
                subshapeID: stableReference.subshapeID,
                tolerance: context.tolerance,
                "Vertex move target vertex could not be resolved."
            )
        }
        guard bodyScope.references.contains(.vertex(vertexID)) else {
            throw error(
                .missingReference,
                featureID: featureID,
                subshapeID: stableReference.subshapeID,
                tolerance: context.tolerance,
                "Vertex move target vertex does not belong to the target body."
            )
        }
        return vertexID
    }

    private func sewingRequest(
        featureID: FeatureID,
        bodyID: BodyID,
        movedVertexID: VertexID,
        displacement: Vector3D,
        context: EvaluationContext
    ) throws -> BRepSewingRequest {
        let model = context.brep
        guard let body = model.bodies[bodyID],
              body.kind == .solid,
              body.shellIDs.count == 1,
              let shellID = body.shellIDs.first,
              let shell = model.shells[shellID],
              let movedVertex = model.vertices[movedVertexID] else {
            throw error(.unsupportedCapability, featureID: featureID, tolerance: context.tolerance, "Vertex move currently requires one single-shell solid body.")
        }
        let sourceEdges = try sourceEdgeMap(shell: shell, model: model)
        let movedPoint = movedVertex.point + displacement
        try movedPoint.validate()
        var containsTarget = false
        var patches: [BRepSewingFacePatch] = []
        for (faceIndex, faceID) in shell.faceIDs.enumerated() {
            guard let face = model.faces[faceID],
                  face.loops.count == 1,
                  let loopID = face.loops.first,
                  let loop = model.loops[loopID],
                  loop.role == .outer,
                  case let .plane(plane) = model.geometry.surfaces[face.surfaceID] else {
                throw error(.unsupportedCapability, featureID: featureID, tolerance: context.tolerance, "Vertex move currently requires planar faces with one straight outer loop and no holes.")
            }
            var boundary = try boundaryVertices(loop: loop, model: model)
            let faceContainsTarget = boundary.contains { $0.sourceVertexID == movedVertexID }
            containsTarget = containsTarget || faceContainsTarget
            boundary = boundary.map { vertex in
                BoundaryVertex(
                    point: vertex.sourceVertexID == movedVertexID ? movedPoint : vertex.point,
                    sourceVertexID: vertex.sourceVertexID
                )
            }
            let outward = face.orientation == .forward ? plane.normal : -plane.normal
            let faceParents = subshapeIDs(for: .face(faceID), context: context)
            let polygons: [[BoundaryVertex]]
            if isPlanar(boundary.map(\.point), tolerance: context.tolerance.distance) {
                polygons = [boundary]
            } else if faceContainsTarget, boundary.count >= 4 {
                let rotated = rotate(boundary, firstVertexID: movedVertexID)
                polygons = (1..<(rotated.count - 1)).map { index in
                    [rotated[0], rotated[index], rotated[index + 1]]
                }
            } else {
                throw error(.unsupportedCapability, featureID: featureID, tolerance: context.tolerance, "Vertex move produced unsupported non-planar topology.")
            }
            for (partIndex, polygon) in polygons.enumerated() {
                patches.append(try patch(
                    stableID: "vertexMove:face:\(faceIndex):part:\(partIndex)",
                    boundary: polygon,
                    outwardHint: outward,
                    faceParents: faceParents,
                    sourceEdges: sourceEdges,
                    context: context
                ))
            }
        }
        guard containsTarget else {
            throw error(.missingReference, featureID: featureID, tolerance: context.tolerance, "Vertex move target vertex does not belong to the target body.")
        }
        return BRepSewingRequest(
            featureID: featureID,
            bodyKind: .solid,
            shells: [BRepSewingShell(stableID: "vertexMove:shell", patches: patches)],
            bodyParentSubshapeIDs: subshapeIDs(for: .body(bodyID), context: context)
        )
    }

    private func sourceEdgeMap(shell: Shell, model: BRepModel) throws -> [VertexPair: EdgeID] {
        var result: [VertexPair: EdgeID] = [:]
        for faceID in shell.faceIDs {
            guard let face = model.faces[faceID] else {
                throw TopologyError.missingReference("Vertex move face is missing.")
            }
            for loopID in face.loops {
                guard let loop = model.loops[loopID] else {
                    throw TopologyError.missingReference("Vertex move loop is missing.")
                }
                for coedge in loop.coedges {
                    guard let edge = model.edges[coedge.edgeID],
                          case .line = model.geometry.curves[edge.curveID] else {
                        throw TopologyError.missingReference("Vertex move requires exact straight source edges.")
                    }
                    result[VertexPair(edge.startVertexID, edge.endVertexID)] = edge.id
                }
            }
        }
        return result
    }

    private func boundaryVertices(loop: Loop, model: BRepModel) throws -> [BoundaryVertex] {
        try loop.coedges.map { coedge in
            guard let edge = model.edges[coedge.edgeID] else {
                throw TopologyError.missingReference("Vertex move edge is missing.")
            }
            let vertexID = coedge.orientation == .forward ? edge.startVertexID : edge.endVertexID
            guard let vertex = model.vertices[vertexID] else {
                throw TopologyError.missingReference("Vertex move vertex is missing.")
            }
            return BoundaryVertex(point: vertex.point, sourceVertexID: vertexID)
        }
    }

    private func patch(
        stableID: String,
        boundary: [BoundaryVertex],
        outwardHint: Vector3D,
        faceParents: [SubshapeID],
        sourceEdges: [VertexPair: EdgeID],
        context: EvaluationContext
    ) throws -> BRepSewingFacePatch {
        guard boundary.count >= 3 else {
            throw error(.topologyFailure, tolerance: context.tolerance, "Vertex move generated a degenerate face patch.")
        }
        var oriented = boundary
        var normal = polygonNormal(oriented.map(\.point))
        guard normal.length > context.tolerance.distance * context.tolerance.distance else {
            throw error(.topologyFailure, tolerance: context.tolerance, "Vertex move generated a zero-area face patch.")
        }
        if normal.dot(outwardHint) < 0.0 {
            oriented.reverse()
            normal = -normal
        }
        let unitNormal = try normal.normalized(tolerance: context.tolerance.distance)
        let surface = Surface3D.plane(Plane3D(origin: oriented[0].point, normal: unitNormal))
        let edges = try oriented.indices.map { index in
            let start = oriented[index]
            let end = oriented[(index + 1) % oriented.count]
            let delta = end.point - start.point
            let startUV = try surface.parameterProjection(of: start.point, tolerance: context.tolerance)
            let endUV = try surface.parameterProjection(of: end.point, tolerance: context.tolerance)
            let sourceEdgeID = sourceEdges[VertexPair(start.sourceVertexID, end.sourceVertexID)]
            return BRepSewingEdge(
                stableID: "\(stableID):edge:\(index)",
                curve: .line(Line3D(
                    origin: start.point,
                    direction: try delta.normalized(tolerance: context.tolerance.distance)
                )),
                startParameter: 0.0,
                endParameter: delta.length,
                startPoint: start.point,
                endPoint: end.point,
                surfaceParameterCurve: .polyline([
                    SurfaceParameter(u: startUV.u, v: startUV.v),
                    SurfaceParameter(u: endUV.u, v: endUV.v),
                ]),
                parentSubshapeIDs: sourceEdgeID.map { subshapeIDs(for: .edge($0), context: context) } ?? [],
                startVertexParentSubshapeIDs: subshapeIDs(for: .vertex(start.sourceVertexID), context: context),
                endVertexParentSubshapeIDs: subshapeIDs(for: .vertex(end.sourceVertexID), context: context)
            )
        }
        return BRepSewingFacePatch(
            stableID: stableID,
            surface: surface,
            orientation: .forward,
            loops: [BRepSewingLoop(stableID: "\(stableID):outer", role: .outer, edges: edges)],
            parentSubshapeIDs: faceParents
        )
    }

    private func isPlanar(_ points: [Point3D], tolerance: Double) -> Bool {
        guard points.count >= 3 else { return false }
        let normal = polygonNormal(points)
        guard normal.length > tolerance * tolerance else { return false }
        let unit = normal / normal.length
        return points.allSatisfy { abs(($0 - points[0]).dot(unit)) <= tolerance }
    }

    private func rotate(
        _ boundary: [BoundaryVertex],
        firstVertexID: VertexID
    ) -> [BoundaryVertex] {
        guard let index = boundary.firstIndex(where: { $0.sourceVertexID == firstVertexID }) else {
            return boundary
        }
        return Array(boundary[index...]) + Array(boundary[..<index])
    }

    private func polygonNormal(_ vertices: [Point3D]) -> Vector3D {
        var normal = Vector3D.zero
        for index in vertices.indices {
            let current = vertices[index]
            let next = vertices[(index + 1) % vertices.count]
            normal = normal + Vector3D(
                x: (current.y - next.y) * (current.z + next.z),
                y: (current.z - next.z) * (current.x + next.x),
                z: (current.x - next.x) * (current.y + next.y)
            )
        }
        return normal
    }

    private func subshapeIDs(for reference: TopologyReference, context: EvaluationContext) -> [SubshapeID] {
        context.subshapeIDs(for: reference)
    }

    private func error(
        _ code: KernelErrorCode,
        featureID: FeatureID? = nil,
        subshapeID: SubshapeID? = nil,
        tolerance: ModelingTolerance,
        _ message: String
    ) -> KernelError {
        KernelError(
            phase: code == .topologyFailure ? .topology : .evaluation,
            code: code,
            featureID: featureID,
            subshapeID: subshapeID,
            tolerance: tolerance,
            message: message
        )
    }

    private struct BoundaryVertex {
        let point: Point3D
        let sourceVertexID: VertexID
    }

    private struct VertexPair: Hashable {
        let first: VertexID
        let second: VertexID

        init(_ first: VertexID, _ second: VertexID) {
            if first < second {
                self.first = first
                self.second = second
            } else {
                self.first = second
                self.second = first
            }
        }
    }
}
