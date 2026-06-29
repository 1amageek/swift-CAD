import CADCore
import CADIR

public struct BooleanFeatureEvaluator: FeatureEvaluating {
    private let booleanEvaluator: any BRepBooleanEvaluating

    public init(booleanEvaluator: any BRepBooleanEvaluating = BoxBRepBooleanEvaluator()) {
        self.booleanEvaluator = booleanEvaluator
    }

    public func evaluate(feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult {
        guard case let .boolean(boolean) = feature.operation else {
            throw FeatureEvaluationError.unsupportedOperation("BooleanFeatureEvaluator only supports boolean features.")
        }
        try boolean.validate()
        let targetBodyIDs = try boolean.targets.map { target in
            try bodyID(for: target.featureID, in: context.generatedNames)
        }
        let toolBodyID = try bodyID(for: boolean.tool.featureID, in: context.generatedNames)
        let toolGeneratedNames = context.generatedNames.filter { _, reference in
            topologyReference(reference, belongsTo: toolBodyID, in: context.brep)
        }

        return try booleanEvaluator.evaluate(
            operation: boolean.operation.sweepBooleanOperation,
            targetBodyIDs: targetBodyIDs,
            toolBodyID: toolBodyID,
            keepTools: boolean.keepTools,
            featureID: feature.id,
            model: context.brep,
            generatedNames: context.generatedNames,
            toolGeneratedNames: toolGeneratedNames,
            tolerance: context.tolerance
        )
    }

    private func bodyID(
        for featureID: FeatureID,
        in generatedNames: [PersistentName: TopologyReference]
    ) throws -> BodyID {
        let name = PersistentName(components: [
            .feature(featureID),
            .generated(GeneratedSubshapeRole.body.rawValue),
        ])
        guard let reference = generatedNames[name] else {
            throw FeatureEvaluationError.missingInput("Boolean body reference could not be resolved.")
        }
        guard case let .body(bodyID) = reference else {
            throw FeatureEvaluationError.invalidGraph("Boolean body reference did not resolve to a body.")
        }
        return bodyID
    }

    private func topologyReference(
        _ reference: TopologyReference,
        belongsTo bodyID: BodyID,
        in model: BRepModel
    ) -> Bool {
        guard let body = model.bodies[bodyID] else {
            return false
        }
        switch reference {
        case .body(let referenceBodyID):
            return referenceBodyID == bodyID
        case .face(let faceID):
            return body.shellIDs.contains { shellID in
                model.shells[shellID]?.faceIDs.contains(faceID) == true
            }
        case .edge(let edgeID):
            return body.shellIDs.contains { shellID in
                model.shells[shellID]?.faceIDs.contains { faceID in
                    model.faces[faceID]?.loops.contains { loopID in
                        model.loops[loopID]?.edges.contains { $0.edgeID == edgeID } == true
                    } == true
                } == true
            }
        case .vertex(let vertexID):
            return body.shellIDs.contains { shellID in
                model.shells[shellID]?.faceIDs.contains { faceID in
                    model.faces[faceID]?.loops.contains { loopID in
                        model.loops[loopID]?.edges.contains { orientedEdge in
                            guard let edge = model.edges[orientedEdge.edgeID] else {
                                return false
                            }
                            return edge.startVertexID == vertexID || edge.endVertexID == vertexID
                        } == true
                    } == true
                } == true
            }
        }
    }
}

private extension BooleanOperation {
    var sweepBooleanOperation: SweepBooleanOperation {
        switch self {
        case .union:
            return .union
        case .difference:
            return .difference
        case .intersect:
            return .intersect
        case .slice:
            return .slice
        }
    }
}
