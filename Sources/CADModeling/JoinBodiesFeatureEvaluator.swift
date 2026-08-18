import CADCore
import CADIR
import CADTopology

public struct JoinBodiesFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    private let validator: any BodyJoinValidating

    package init(validator: any BodyJoinValidating) {
        self.validator = validator
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
        guard case let .joinBodies(join) = feature.operation else {
            throw error(
                .invalidInput,
                featureID: feature.id,
                tolerance: context.tolerance,
                "Join bodies evaluator requires a joinBodies feature."
            )
        }
        try FeatureEvaluationBoundary.validateRequest(featureID: feature.id, tolerance: context.tolerance) {
            try join.validate()
        }
        try FeatureEvaluationBoundary.validateExactInput(
            context.brep,
            featureID: feature.id,
            tolerance: context.tolerance
        )
        let bodyIDs = try join.targets.map { target in
            try context.bodyID(generatedBy: target.featureID)
        }
        let bodies = try bodyIDs.map { bodyID -> Body in
            guard let body = context.brep.bodies[bodyID] else {
                throw TopologyError.missingReference("Join bodies source body is missing.")
            }
            guard body.kind == .solid else {
                throw error(
                    .invalidInput,
                    featureID: feature.id,
                    tolerance: context.tolerance,
                    "Join bodies requires every source body to be a solid."
                )
            }
            return body
        }
        try validator.validateDisjointMaterial(
            bodyIDs: bodyIDs,
            in: context.brep,
            tolerance: context.tolerance
        )

        let joinedBodyID = BodyID()
        var replacement = try BRepBodySubmodelExtractor().extract(
            bodyIDs: Set(bodyIDs),
            from: context.brep
        )
        for bodyID in bodyIDs {
            replacement.bodies.removeValue(forKey: bodyID)
        }
        let components = try bodies.flatMap { body throws -> [SolidShellComponent] in
            guard case .solid(let components) = body.topology else {
                throw error(
                    .topologyFailure,
                    featureID: feature.id,
                    tolerance: context.tolerance,
                    "A validated solid body has inconsistent explicit topology."
                )
            }
            return components
        }
        replacement.bodies[joinedBodyID] = Body(
            id: joinedBodyID,
            solidComponents: components
        )
        let model = try BRepBodyModelReplacer().replacing(
            bodyIDs: Set(bodyIDs),
            with: replacement,
            in: context.brep
        )
        try model.validate(level: .volumetric, tolerance: context.tolerance)

        let joinedSubshapeID = SubshapeID(
            featureID: feature.id,
            role: GeneratedSubshapeRole.body.rawValue,
            ordinal: 0
        )
        let removedSubshapeIDs = Set(bodyIDs.flatMap { bodyID in
            context.subshapeIDs(for: .body(bodyID))
        })
        return EvaluationResult(
            brep: model,
            subshapes: [joinedSubshapeID: .body(joinedBodyID)],
            removedSubshapeIDs: removedSubshapeIDs,
            lineage: [
                joinedSubshapeID: TopologyLineage(
                    output: joinedSubshapeID,
                    parents: Array(removedSubshapeIDs),
                    relation: .merged
                ),
            ]
        )
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
