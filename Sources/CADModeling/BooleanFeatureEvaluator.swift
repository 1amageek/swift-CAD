import CADCore
import CADIR
import CADTopology

public struct BooleanFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    private let applicator: any BooleanOperationApplying

    public init(applicator: any BooleanOperationApplying) {
        self.applicator = applicator
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
        let result = try evaluateUnvalidated(feature: feature, context: context)
        return try ValidatedFeatureEvaluation(
            validating: result,
            tolerance: context.tolerance
        )
    }

    private func evaluateUnvalidated(
        feature: FeatureNode,
        context: EvaluationContext
    ) throws -> EvaluationResult {
        try context.tolerance.validate()
        guard case let .boolean(boolean) = feature.operation else {
            throw KernelError.unsupportedEvaluation(
                tolerance: context.tolerance,
                message: "BooleanFeatureEvaluator only supports boolean features."
            )
        }
        try FeatureEvaluationBoundary.validateRequest(
            featureID: feature.id,
            tolerance: context.tolerance
        ) {
            try boolean.validate()
        }
        let targetBodyIDs = try boolean.targets.map { target in
            try context.bodyID(generatedBy: target.featureID)
        }
        let toolBodyID = try context.bodyID(generatedBy: boolean.tool.featureID)
        let toolSubshapes = context.subshapes.entries.filter { _, reference in
            topologyReference(reference, belongsTo: toolBodyID, in: context.brep)
        }

        return try FeatureEvaluationBoundary.evaluate(
            featureID: feature.id,
            tolerance: context.tolerance
        ) {
            try applicator.apply(
                operation: boolean.operation,
                targetBodyIDs: targetBodyIDs,
                toolBodyID: toolBodyID,
                keepTools: boolean.keepTools,
                featureID: feature.id,
                model: context.brep,
                subshapes: context.subshapes.entries,
                toolSubshapes: toolSubshapes,
                inputLineage: context.lineage,
                tolerance: context.tolerance
            )
        }
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
