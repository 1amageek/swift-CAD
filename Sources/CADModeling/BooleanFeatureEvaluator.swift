import CADCore
import CADGeometry
import CADIR
import CADTopology

public struct BooleanFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    private let applicator: any BooleanOperationApplying
    private let toolRelocator: (any ExactBodyPatternRebuilding)?

    /// An evaluator for Booleans whose tool is combined where it was evaluated.
    public init(applicator: any BooleanOperationApplying) {
        self.applicator = applicator
        self.toolRelocator = nil
    }

    /// An evaluator that also moves a placed tool onto its targets with `toolRelocator`.
    package init(
        applicator: any BooleanOperationApplying,
        toolRelocator: any ExactBodyPatternRebuilding
    ) {
        self.applicator = applicator
        self.toolRelocator = toolRelocator
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
            throw FeatureEvaluationError.invalidGraph(
                "BooleanFeatureEvaluator received a non-boolean feature."
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
        if let placement = boolean.toolPlacement {
            return try evaluatePlacedTool(
                boolean,
                placement: placement,
                targetBodyIDs: targetBodyIDs,
                toolBodyID: toolBodyID,
                featureID: feature.id,
                context: context
            )
        }
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

    /// Moves the tool rigidly onto the targets under a temporary stage identity, combines, then
    /// publishes the result as if the original tool had been combined: the stage identities are
    /// consumed with the tool, the original tool topology is removed, and lineage that ran through
    /// the moved tool is traced back to the original tool subshapes.
    private func evaluatePlacedTool(
        _ boolean: BooleanFeature,
        placement: RigidTransform3D,
        targetBodyIDs: [BodyID],
        toolBodyID: BodyID,
        featureID: FeatureID,
        context: EvaluationContext
    ) throws -> EvaluationResult {
        guard let toolRelocator else {
            throw KernelError(
                phase: .evaluation,
                code: .unsupportedCapability,
                featureID: featureID,
                tolerance: context.tolerance,
                message: "This evaluator cannot move a placed Boolean tool."
            )
        }
        try placement.validate(tolerance: context.tolerance)
        let stageID = featureEvaluationStageID(featureID: featureID, domain: .booleanToolPlacement, ordinal: 0)
        let relocated = try FeatureEvaluationBoundary.evaluate(
            featureID: featureID,
            tolerance: context.tolerance
        ) {
            try toolRelocator.relocate(
                featureID: stageID,
                sourceBodyID: toolBodyID,
                transform: placement,
                stablePrefix: "boolean:placedTool",
                context: context
            )
        }
        let relocatedBodyIDs = Set(relocated.subshapes.values.compactMap { reference -> BodyID? in
            guard case let .body(bodyID) = reference else { return nil }
            return bodyID
        })
        guard relocatedBodyIDs.count == 1, let relocatedToolBodyID = relocatedBodyIDs.first else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                featureID: featureID,
                tolerance: context.tolerance,
                message: "Moving the Boolean tool did not publish exactly one body."
            )
        }
        var subshapes = context.subshapes.entries
        for subshapeID in relocated.removedSubshapeIDs {
            subshapes.removeValue(forKey: subshapeID)
        }
        subshapes.merge(relocated.subshapes) { _, moved in moved }
        var inputLineage = context.lineage
        inputLineage.merge(relocated.lineage) { _, moved in moved }

        var result = try FeatureEvaluationBoundary.evaluate(
            featureID: featureID,
            tolerance: context.tolerance
        ) {
            try applicator.apply(
                operation: boolean.operation,
                targetBodyIDs: targetBodyIDs,
                toolBodyID: relocatedToolBodyID,
                keepTools: false,
                featureID: featureID,
                model: relocated.brep,
                subshapes: subshapes,
                toolSubshapes: relocated.subshapes,
                inputLineage: inputLineage,
                tolerance: context.tolerance
            )
        }
        let stageSubshapeIDs = Set(relocated.subshapes.keys)
        guard result.subshapes.keys.allSatisfy({ stageSubshapeIDs.contains($0) == false }) else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                featureID: featureID,
                tolerance: context.tolerance,
                message: "A placed Boolean tool left a temporary identity in its result."
            )
        }
        result.removedSubshapeIDs = result.removedSubshapeIDs
            .subtracting(stageSubshapeIDs)
            .union(relocated.removedSubshapeIDs)
        result.lineage = result.lineage.mapValues { entry in
            var parents = Set<SubshapeID>()
            for parent in entry.parents {
                if stageSubshapeIDs.contains(parent) {
                    parents.formUnion(relocated.lineage[parent]?.parents ?? [])
                } else {
                    parents.insert(parent)
                }
            }
            return TopologyLineage(output: entry.output, parents: parents.sorted(), relation: entry.relation)
        }.withRelationsDerivedFromParents()
        return result
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
