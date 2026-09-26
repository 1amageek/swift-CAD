import CADCore
import CADIR

public struct MirrorFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    private let rebuilder: any ExactBodyPatternRebuilding
    private let cutter: (any BodyHalfSpaceCutting)?

    /// An evaluator for mirrors that do not cut at their plane.
    public init(
        sewer: any BRepSewing,
        unionApplicator: any BooleanOperationApplying,
        separationValidator: any BodyJoinValidating
    ) {
        self.rebuilder = DefaultExactBodyPatternRebuilder(
            sewer: sewer,
            unionApplicator: unionApplicator,
            separationValidator: separationValidator
        )
        self.cutter = nil
    }

    /// An evaluator that also cuts the target at the mirror plane with `cutter`.
    package init(
        sewer: any BRepSewing,
        unionApplicator: any BooleanOperationApplying,
        separationValidator: any BodyJoinValidating,
        cutter: any BodyHalfSpaceCutting
    ) {
        self.rebuilder = DefaultExactBodyPatternRebuilder(
            sewer: sewer,
            unionApplicator: unionApplicator,
            separationValidator: separationValidator
        )
        self.cutter = cutter
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
        guard case let .mirror(mirror) = feature.operation else {
            throw error(
                .invalidInput,
                featureID: feature.id,
                tolerance: context.tolerance,
                "Mirror evaluator requires a mirror feature."
            )
        }
        try FeatureEvaluationBoundary.validateRequest(featureID: feature.id, tolerance: context.tolerance) {
            try mirror.validate(tolerance: context.tolerance)
        }
        try FeatureEvaluationBoundary.validateExactInput(
            context,
            featureID: feature.id,
            tolerance: context.tolerance
        )
        let bodyID = try targetBodyID(mirror.target.featureID, featureID: feature.id, context: context)
        guard mirror.cutsAtPlane else {
            return try reflect(mirror, bodyID: bodyID, featureID: feature.id, context: context)
        }
        guard let cutter else {
            throw error(
                .unsupportedCapability,
                featureID: feature.id,
                tolerance: context.tolerance,
                "This evaluator cannot cut a mirror target at its plane."
            )
        }
        let stageID = featureEvaluationStageID(featureID: feature.id, domain: .mirrorCut, ordinal: 0)
        guard let cut = try cutter.cut(
            bodyID: bodyID,
            planeOrigin: mirror.planeOrigin,
            planeNormal: mirror.planeNormal,
            featureID: stageID,
            context: context
        ) else {
            // The target already lies on the kept side, so the cut keeps all of it.
            return try reflect(mirror, bodyID: bodyID, featureID: feature.id, context: context)
        }
        let cutBodyIDs = Set(cut.subshapes.values.compactMap { reference -> BodyID? in
            guard case let .body(id) = reference else { return nil }
            return id
        })
        guard cutBodyIDs.count == 1, let cutBodyID = cutBodyIDs.first else {
            throw error(
                .topologyFailure,
                featureID: feature.id,
                tolerance: context.tolerance,
                "Cutting the mirror target at its plane must keep exactly one body."
            )
        }
        var staged = context
        staged.brep = cut.brep
        for subshapeID in cut.removedSubshapeIDs {
            staged.subshapes.entries.removeValue(forKey: subshapeID)
        }
        staged.subshapes.entries.merge(cut.subshapes) { _, cutEntry in cutEntry }
        staged.lineage.merge(cut.lineage) { _, cutEntry in cutEntry }
        // The kept material lies against the plane, so it and its reflection meet only there: a
        // combined output sews the two together instead of intersecting them.
        var result = mirror.output == .combined
            ? try rebuilder.glueReflection(
                featureID: feature.id,
                sourceBodyID: cutBodyID,
                reflection: try ExactPatternTransform.mirrored(
                    across: mirror.planeOrigin,
                    normal: mirror.planeNormal,
                    tolerance: context.tolerance
                ),
                planeOrigin: mirror.planeOrigin,
                planeNormal: mirror.planeNormal,
                stablePrefix: "mirror",
                context: staged
            )
            : try reflect(mirror, bodyID: cutBodyID, featureID: feature.id, context: staged)

        // Publish the result as if the target had been mirrored directly: the cut stage's
        // identities are consumed, the target's are removed, and lineage through the cut body
        // leads back to the target.
        let stageSubshapeIDs = Set(cut.subshapes.keys)
        guard result.subshapes.keys.allSatisfy({ !stageSubshapeIDs.contains($0) }) else {
            throw error(
                .topologyFailure,
                featureID: feature.id,
                tolerance: context.tolerance,
                "A cut mirror left a temporary identity in its result."
            )
        }
        result.removedSubshapeIDs = result.removedSubshapeIDs
            .subtracting(stageSubshapeIDs)
            .union(cut.removedSubshapeIDs)
        result.lineage = result.lineage.mapValues { entry in
            var parents = Set<SubshapeID>()
            for parent in entry.parents {
                if stageSubshapeIDs.contains(parent) {
                    parents.formUnion(cut.lineage[parent]?.parents ?? [])
                } else {
                    parents.insert(parent)
                }
            }
            return TopologyLineage(output: entry.output, parents: parents.sorted(), relation: entry.relation)
        }.withRelationsDerivedFromParents()
        return result
    }

    /// Replaces `bodyID` with the mirror's output built from it.
    private func reflect(
        _ mirror: MirrorFeature,
        bodyID: BodyID,
        featureID: FeatureID,
        context: EvaluationContext
    ) throws -> EvaluationResult {
        let reflection = try ExactPatternTransform.mirrored(
            across: mirror.planeOrigin,
            normal: mirror.planeNormal,
            tolerance: context.tolerance
        )
        switch mirror.output {
        case .combined:
            return try rebuilder.rebuild(
                featureID: featureID,
                sourceBodyID: bodyID,
                transforms: [.translated(by: .zero), reflection],
                stablePrefix: "mirror",
                context: context
            )
        case .reflection:
            return try rebuilder.relocate(
                featureID: featureID,
                sourceBodyID: bodyID,
                transform: reflection,
                stablePrefix: "mirror",
                context: context
            )
        case .kept:
            return try rebuilder.relocate(
                featureID: featureID,
                sourceBodyID: bodyID,
                transform: .translated(by: .zero),
                stablePrefix: "mirror",
                context: context
            )
        }
    }

    private func targetBodyID(
        _ sourceFeatureID: FeatureID,
        featureID: FeatureID,
        context: EvaluationContext
    ) throws -> BodyID {
        try context.bodyID(generatedBy: sourceFeatureID)
    }

    private func error(
        _ code: KernelErrorCode,
        featureID: FeatureID? = nil,
        tolerance: ModelingTolerance,
        _ message: String
    ) -> KernelError {
        KernelError(
            phase: .evaluation,
            code: code,
            featureID: featureID,
            tolerance: tolerance,
            message: message
        )
    }
}
