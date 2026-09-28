import CADCore
import CADGeometry
import CADIR
import CADTopology

public struct BooleanFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    private let applicator: any BooleanOperationApplying
    private let toolRelocator: (any ExactBodyPatternRebuilding)?

    /// An evaluator for Booleans whose operands are all combined where they were evaluated.
    public init(applicator: any BooleanOperationApplying) {
        self.applicator = applicator
        self.toolRelocator = nil
    }

    /// An evaluator that also moves placed operands into the result's frame with `toolRelocator`.
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
        let targetBodyIDs = try boolean.targets.map { try context.bodyID(generatedBy: $0.featureID) }
        let toolBodyIDs = try boolean.tools.map { try context.bodyID(generatedBy: $0.featureID) }
        return try evaluateStaged(
            boolean, targetBodyIDs: targetBodyIDs, toolBodyIDs: toolBodyIDs, featureID: feature.id, context: context
        )
    }

    /// Moves every placed operand rigidly into the result's frame, unites several tools into one,
    /// combines, and publishes the result as if the inputs had been combined directly. The result
    /// replaces the targets; Keep Tools puts every tool back, unchanged, where it was evaluated.
    private func evaluateStaged(
        _ boolean: BooleanFeature,
        targetBodyIDs: [BodyID],
        toolBodyIDs: [BodyID],
        featureID: FeatureID,
        context: EvaluationContext
    ) throws -> EvaluationResult {
        var stages = FeatureEvaluationStages(context)
        func relocated(_ bodyID: BodyID, placement: RigidTransform3D?, ordinal: Int) throws -> BodyID {
            guard let placement else { return bodyID }
            guard let toolRelocator else {
                throw KernelError(
                    phase: .evaluation,
                    code: .unsupportedCapability,
                    featureID: featureID,
                    tolerance: context.tolerance,
                    message: "This evaluator cannot move a placed Boolean operand."
                )
            }
            try placement.validate(tolerance: context.tolerance)
            let stageID = featureEvaluationStageID(featureID: featureID, domain: .booleanOperandPlacement, ordinal: UInt64(ordinal))
            let staged = stages.context
            let moved = try FeatureEvaluationBoundary.evaluate(featureID: featureID, tolerance: context.tolerance) {
                try toolRelocator.relocate(
                    featureID: stageID,
                    sourceBodyID: bodyID,
                    transform: placement,
                    stablePrefix: "boolean:placedOperand",
                    context: staged
                )
            }
            stages.apply(moved)
            return try stages.publishedBody(of: moved, featureID: featureID, what: "Moving a Boolean operand")
        }
        let targets = try zip(targetBodyIDs, boolean.targets).enumerated().map { ordinal, pair in
            try relocated(pair.0, placement: pair.1.placement, ordinal: ordinal)
        }
        var tools = try zip(toolBodyIDs, boolean.tools).enumerated().map { ordinal, pair in
            try relocated(pair.0, placement: pair.1.placement, ordinal: targetBodyIDs.count + ordinal)
        }
        // The tools act as one region: unite them, one after another.
        var unionOrdinal: UInt64 = 0
        while tools.count > 1 {
            let stageID = featureEvaluationStageID(featureID: featureID, domain: .booleanToolUnion, ordinal: unionOrdinal)
            unionOrdinal += 1
            let united = try combine(.union, targets: [tools[0]], tool: tools[1], featureID: stageID, context: stages.context)
            stages.apply(united)
            tools = [try stages.publishedBody(of: united, featureID: featureID, what: "Uniting the Boolean tools")] + tools.dropFirst(2)
        }
        let final = try combine(
            boolean.operation, targets: targets, tool: tools[0], featureID: featureID, context: stages.context
        )
        let published = try stages.publish(final, featureID: featureID)
        guard boolean.keepTools else { return published }
        return try stages.restoringInputBodies(toolBodyIDs, into: published)
    }

    /// One pass of the Boolean pipeline in `context`, consuming its operands.
    private func combine(
        _ operation: BooleanOperation,
        targets: [BodyID],
        tool: BodyID,
        featureID: FeatureID,
        context: EvaluationContext
    ) throws -> EvaluationResult {
        let toolSubshapes = context.subshapes.entries.filter { _, reference in
            context.brep.contains(reference, inBody: tool)
        }
        return try FeatureEvaluationBoundary.evaluate(featureID: featureID, tolerance: context.tolerance) {
            try applicator.apply(
                operation: operation,
                targetBodyIDs: targets,
                toolBodyID: tool,
                keepTools: false,
                featureID: featureID,
                model: context.brep,
                subshapes: context.subshapes.entries,
                toolSubshapes: toolSubshapes,
                inputLineage: context.lineage,
                tolerance: context.tolerance
            )
        }
    }
}
