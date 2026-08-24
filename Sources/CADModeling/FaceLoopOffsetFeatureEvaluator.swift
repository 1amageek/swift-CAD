import Foundation
import CADCore
import CADIR
import CADTopology

public struct FaceLoopOffsetFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    private let resolver: ParameterResolving
    private let subshapeResolver: any StableSubshapeResolving

    public init(
        resolver: ParameterResolving = ParameterResolver(),
        subshapeResolver: any StableSubshapeResolving = StableSubshapeResolver()
    ) {
        self.resolver = resolver
        self.subshapeResolver = subshapeResolver
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
            try evaluateUnvalidated(feature: feature, context: context)
        }
    }

    private func evaluateUnvalidated(
        feature: FeatureNode,
        context: EvaluationContext
    ) throws -> EvaluationResult {
        guard case let .faceLoopOffset(faceLoopOffset) = feature.operation else {
            throw KernelError.unsupportedEvaluation(tolerance: context.tolerance, message:
                "FaceLoopOffsetFeatureEvaluator only supports faceLoopOffset."
            )
        }
        try FeatureEvaluationBoundary.validateRequest(
            featureID: feature.id,
            tolerance: context.tolerance
        ) {
            try faceLoopOffset.validate()
        }
        try FeatureEvaluationBoundary.validateExactInput(
            context,
            featureID: feature.id,
            tolerance: context.tolerance
        )
        let distance = try resolvedDistance(faceLoopOffset.distance, context: context)
        var model = context.brep

        let bodyID = try targetBodyID(for: faceLoopOffset.target.featureID, context: context)
        let faceID = try targetFaceID(for: faceLoopOffset.face, context: context)
        guard try body(bodyID, contains: faceID, in: model) else {
            throw FeatureEvaluationError.missingInput("Face loop offset target face is not on the target body.")
        }
        let parentResolver = LiveTopologyParentResolver()
        let bodyParent = try parentResolver.resolve(
            .body(bodyID),
            in: context.subshapes,
            featureID: feature.id,
            tolerance: context.tolerance
        )
        let generatedSubshapes = try splitConvexPlanarFace(
            faceID,
            distance: distance,
            featureID: feature.id,
            bodyID: bodyID,
            tolerance: context.tolerance,
            model: &model
        )
        let lineage = topologyLineage(
            subshapes: generatedSubshapes,
            bodyParent: bodyParent
        )
        return EvaluationResult(
            brep: model,
            subshapes: generatedSubshapes,
            removedSubshapeIDs: [bodyParent],
            lineage: lineage
        )
    }

    private func resolvedDistance(
        _ expression: CADExpression,
        context: EvaluationContext
    ) throws -> Double {
        let quantity = try resolver.evaluate(expression, parameters: context.parameters, variables: [:])
        guard quantity.kind == .length else {
            throw UnitError.expectedQuantity(
                operation: "faceLoopOffset.distance",
                expected: .length,
                actual: quantity.kind
            )
        }
        guard quantity.value > context.tolerance.distance else {
            throw FeatureEvaluationError.invalidDistance(quantity.value)
        }
        return quantity.value
    }

    private func targetBodyID(
        for featureID: FeatureID,
        context: EvaluationContext
    ) throws -> BodyID {
        try context.bodyID(generatedBy: featureID)
    }

    private func targetFaceID(
        for stableReference: StableSubshapeReference,
        context: EvaluationContext
    ) throws -> FaceID {
        let reference = try subshapeResolver.topologyReference(
            for: stableReference,
            model: context.brep,
            subshapes: context.subshapes,
            lineage: context.lineage,
            tolerance: context.tolerance
        )
        guard case let .face(faceID) = reference else {
            throw FeatureEvaluationError.missingInput("Face loop offset target face could not be resolved.")
        }
        return faceID
    }

    private func body(
        _ bodyID: BodyID,
        contains faceID: FaceID,
        in model: BRepModel
    ) throws -> Bool {
        guard let body = model.bodies[bodyID] else {
            throw TopologyError.missingReference("Missing face loop offset body \(bodyID).")
        }
        for shellID in body.shellIDs {
            guard let shell = model.shells[shellID] else {
                throw TopologyError.missingReference("Missing face loop offset shell \(shellID).")
            }
            if shell.faceIDs.contains(faceID) {
                return true
            }
        }
        return false
    }

    private func splitConvexPlanarFace(
        _ faceID: FaceID,
        distance: Double,
        featureID: FeatureID,
        bodyID: BodyID,
        tolerance: ModelingTolerance,
        model: inout BRepModel
    ) throws -> [SubshapeID: TopologyReference] {
        guard var face = model.faces[faceID] else {
            throw TopologyError.missingReference("Missing face loop offset face \(faceID).")
        }
        guard face.loops.count == 1,
              let outerLoopID = face.loops.first,
              let outerLoop = model.loops[outerLoopID],
              outerLoop.role == .outer else {
            throw KernelError.unsupportedEvaluation(tolerance: tolerance, message:
                "Face loop offset currently requires one outer loop with no existing inner loops."
            )
        }
        guard let surface = model.geometry.surfaces[face.surfaceID],
              case let .plane(plane) = surface else {
            throw KernelError.unsupportedEvaluation(tolerance: tolerance, message:
                "Face loop offset currently supports planar faces only."
            )
        }
        try plane.validate(tolerance: tolerance)
        guard outerLoop.edges.count >= 3 else {
            throw KernelError.unsupportedEvaluation(tolerance: tolerance, message:
                "Face loop offset requires at least three boundary edges."
            )
        }
        for orientedEdge in outerLoop.edges {
            guard let edge = model.edges[orientedEdge.edgeID],
                  let curve = model.geometry.curves[edge.curveID],
                  case .line = curve else {
                throw KernelError.unsupportedEvaluation(tolerance: tolerance, message:
                    "Face loop offset requires a line-only planar face loop."
                )
            }
        }

        let outerVertexIDs = try model.orderedVertexIDs(for: outerLoopID)
        let outerPoints = try outerVertexIDs.map { vertexID -> Point3D in
            guard let vertex = model.vertices[vertexID] else {
                throw TopologyError.missingReference("Missing face loop offset vertex \(vertexID).")
            }
            return vertex.point
        }
        let frame = try PlanarFaceFrame(plane: plane, tolerance: tolerance)
        let outer2D = outerPoints.map(frame.localPoint)
        let polygon = try StrictlyConvexPlanarLoop(points: outer2D, tolerance: tolerance)
        let inner2D = try polygon.inset(distance: distance, tolerance: tolerance)
        let innerPoints = inner2D.map(frame.worldPoint)
        var topologyIDs = FeatureTopologyIDAllocator(featureID: featureID)
        var generatedSubshapes: [SubshapeID: TopologyReference] = [:]
        let innerVertexIDs = innerPoints.enumerated().map { index, point -> VertexID in
            let vertexID = topologyIDs.nextVertexID()
            model.vertices[vertexID] = Vertex(id: vertexID, point: point)
            generatedSubshapes[subshapeID(featureID, "offsetVertex", index)] = .vertex(vertexID)
            return vertexID
        }

        var innerEdgeIDs: [EdgeID] = []
        for index in innerVertexIDs.indices {
            let startVertexID = innerVertexIDs[index]
            let endVertexID = innerVertexIDs[(index + 1) % innerVertexIDs.count]
            let start = innerPoints[index]
            let end = innerPoints[(index + 1) % innerPoints.count]
            let length = (end - start).length
            guard length > tolerance.distance else {
                throw FeatureEvaluationError.invalidDistance(length)
            }
            let direction = try (end - start).normalized(tolerance: tolerance.distance)
            let curveID = topologyIDs.nextCurveID()
            let edgeID = topologyIDs.nextEdgeID()
            model.geometry.curves[curveID] = .line(Line3D(origin: start, direction: direction))
            model.edges[edgeID] = Edge(
                id: edgeID,
                curveID: curveID,
                startVertexID: startVertexID,
                endVertexID: endVertexID,
                trim: CurveTrim(startParameter: 0.0, endParameter: length)
            )
            innerEdgeIDs.append(edgeID)
            generatedSubshapes[subshapeID(featureID, "offsetEdge", index)] = .edge(edgeID)
        }

        let ringInnerLoopID = topologyIDs.nextLoopID()
        let centerLoopID = topologyIDs.nextLoopID()
        let reversedInnerEdges = innerEdgeIDs.indices.reversed().map { index in
            let nextIndex = (index + 1) % innerEdgeIDs.count
            return Coedge(
                edgeID: innerEdgeIDs[index],
                orientation: .reversed,
                surfaceParameterCurve: surfaceParameterCurve(from: inner2D[nextIndex], to: inner2D[index])
            )
        }
        let centerEdges = innerEdgeIDs.indices.map { index in
            let nextIndex = (index + 1) % innerEdgeIDs.count
            return Coedge(
                edgeID: innerEdgeIDs[index],
                orientation: .forward,
                surfaceParameterCurve: surfaceParameterCurve(from: inner2D[index], to: inner2D[nextIndex])
            )
        }
        model.loops[ringInnerLoopID] = Loop(id: ringInnerLoopID, role: .inner, edges: reversedInnerEdges)
        model.loops[centerLoopID] = Loop(id: centerLoopID, role: .outer, edges: centerEdges)

        let centerFaceID = topologyIDs.nextFaceID()
        face.loops.append(ringInnerLoopID)
        model.faces[faceID] = face
        model.faces[centerFaceID] = Face(
            id: centerFaceID,
            surfaceID: face.surfaceID,
            loops: [centerLoopID],
            orientation: face.orientation
        )
        try append(centerFaceID, after: faceID, in: &model)
        generatedSubshapes[SubshapeID(
            featureID: featureID,
            role: GeneratedSubshapeRole.body.rawValue,
            ordinal: 0
        )] = .body(bodyID)
        generatedSubshapes[subshapeID(featureID, "centerFace", 0)] = .face(centerFaceID)
        return generatedSubshapes
    }

    private func topologyLineage(
        subshapes: [SubshapeID: TopologyReference],
        bodyParent: SubshapeID
    ) -> [SubshapeID: TopologyLineage] {
        Dictionary(uniqueKeysWithValues: subshapes.map { output, reference in
            let entry: TopologyLineage
            switch reference {
            case .body:
                entry = TopologyLineage(
                    output: output,
                    parents: [bodyParent],
                    relation: .preserved
                )
            case .face:
                entry = TopologyLineage(output: output, relation: .generated)
            case .edge, .vertex:
                entry = TopologyLineage(output: output, relation: .generated)
            }
            return (output, entry)
        })
    }

    private func append(
        _ insertedFaceID: FaceID,
        after faceID: FaceID,
        in model: inout BRepModel
    ) throws {
        for (shellID, var shell) in model.shells {
            guard let index = shell.faceIDs.firstIndex(of: faceID) else {
                continue
            }
            shell.faceIDs.insert(insertedFaceID, at: shell.faceIDs.index(after: index))
            model.shells[shellID] = shell
            return
        }
        throw TopologyError.missingReference("Face loop offset shell for face \(faceID) was not found.")
    }

    private func surfaceParameterCurve(from start: Point2D, to end: Point2D) -> SurfaceParameterCurve {
        .affine(
            origin: start,
            direction: Point2D(x: end.x - start.x, y: end.y - start.y),
            startParameter: 0.0,
            endParameter: 1.0
        )
    }

    private func subshapeID(
        _ featureID: FeatureID,
        _ role: String,
        _ ordinal: Int
    ) -> SubshapeID {
        SubshapeID(
            featureID: featureID,
            role: SubshapeIdentityRole.compose(
                generatedRole: "faceLoopOffset",
                subshapeRole: role
            ),
            ordinal: ordinal
        )
    }
}
