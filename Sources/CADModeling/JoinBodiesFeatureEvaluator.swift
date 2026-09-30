import CADCore
import CADIR
import CADTopology

/// Joins bodies as its mode says: solids whose material does not meet become the components of one
/// solid body, and sheets are sewn along the edges where they meet exactly into a sheet or a solid
/// (`SheetBodyJoining`).
public struct JoinBodiesFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    private let validator: any BodyJoinValidating
    private let sheetJoiner: any SheetBodyJoining

    package init(validator: any BodyJoinValidating, sheetJoiner: any SheetBodyJoining) {
        self.validator = validator
        self.sheetJoiner = sheetJoiner
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
            context,
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
            return body
        }
        let removedSubshapeIDs = Set(bodyIDs.flatMap { bodyID in
            context.subshapeIDs(for: .body(bodyID))
        })
        if join.mode != .solidComponents {
            guard bodies.allSatisfy({ $0.kind == .sheet }) else {
                throw error(
                    .invalidInput,
                    featureID: feature.id,
                    tolerance: context.tolerance,
                    "Join bodies sews sheets only."
                )
            }
            let sewn = try sheetJoiner.joinSheets(
                bodyIDs: bodyIDs, closed: join.mode == .sewnSolid, featureID: feature.id, context: context
            )
            // Sewing rebuilds every face, edge and vertex, so every subshape of the sources goes.
            let replacedSubshapeIDs = try bodyIDs.reduce(into: Set<SubshapeID>()) { replaced, bodyID in
                replaced.formUnion(try BodyTopologyScope(bodyID: bodyID, model: context.brep).subshapeIDs(in: context.subshapes))
            }
            let model = try BRepBodyModelReplacer().replacing(
                bodyIDs: Set(bodyIDs),
                with: sewn.brep,
                in: context.brep
            )
            return EvaluationResult(
                brep: model,
                subshapes: sewn.subshapes,
                removedSubshapeIDs: replacedSubshapeIDs.union(removedSubshapeIDs),
                lineage: sewn.lineage
            )
        }
        guard bodies.allSatisfy({ $0.kind == .solid }) else {
            throw error(
                .invalidInput,
                featureID: feature.id,
                tolerance: context.tolerance,
                "Join bodies combines solids only; sheets are sewn."
            )
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

        let joinedSubshapeID = SubshapeID(
            featureID: feature.id,
            role: GeneratedSubshapeRole.body.rawValue,
            ordinal: 0
        )
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
