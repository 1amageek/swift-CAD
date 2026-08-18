import CADCore
import CADIR
import CADTopology

public struct UnjoinBodyFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    public init() {}

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
        guard case let .unjoinBody(unjoin) = feature.operation else {
            throw error(
                .invalidInput,
                featureID: feature.id,
                tolerance: context.tolerance,
                "Unjoin body evaluator requires an unjoinBody feature."
            )
        }
        try FeatureEvaluationBoundary.validateRequest(featureID: feature.id, tolerance: context.tolerance) {
            try unjoin.validate()
        }
        try FeatureEvaluationBoundary.validateExactInput(
            context.brep,
            featureID: feature.id,
            tolerance: context.tolerance
        )
        let bodyID = try context.bodyID(generatedBy: unjoin.target.featureID)
        guard let body = context.brep.bodies[bodyID] else {
            throw TopologyError.missingReference("Unjoin body source body is missing.")
        }
        let componentTopologies: [BodyTopology]
        switch body.topology {
        case .solid(let components):
            componentTopologies = components.map { .solid(components: [$0]) }
        case .sheet(let shellIDs):
            componentTopologies = shellIDs.map { .sheet(shellIDs: [$0]) }
        }
        guard componentTopologies.count >= 2 else {
            throw error(
                .invalidInput,
                featureID: feature.id,
                tolerance: context.tolerance,
                "Unjoin body requires a source body with at least two disconnected components."
            )
        }

        var replacement = try BRepBodySubmodelExtractor().extract(
            bodyIDs: [bodyID],
            from: context.brep
        )
        replacement.bodies.removeValue(forKey: bodyID)
        var subshapes: [SubshapeID: TopologyReference] = [:]
        var lineage: [SubshapeID: TopologyLineage] = [:]
        let removedSubshapeIDs = Set(context.subshapeIDs(for: .body(bodyID)))
        guard removedSubshapeIDs.count == 1 else {
            throw error(
                .topologyFailure,
                featureID: feature.id,
                tolerance: context.tolerance,
                "Unjoin body requires exactly one live subshape identity for the source body."
            )
        }
        let parents = Array(removedSubshapeIDs)
        for (ordinal, topology) in componentTopologies.enumerated() {
            let splitBodyID = BodyID()
            replacement.bodies[splitBodyID] = Body(
                id: splitBodyID,
                topology: topology
            )
            let splitSubshapeID = SubshapeID(
                featureID: feature.id,
                role: GeneratedSubshapeRole.body.rawValue,
                ordinal: ordinal
            )
            subshapes[splitSubshapeID] = .body(splitBodyID)
            lineage[splitSubshapeID] = TopologyLineage(
                output: splitSubshapeID,
                parents: parents,
                relation: .split
            )
        }
        let model = try BRepBodyModelReplacer().replacing(
            bodyIDs: [bodyID],
            with: replacement,
            in: context.brep
        )
        try model.validate(level: .volumetric, tolerance: context.tolerance)

        return EvaluationResult(
            brep: model,
            subshapes: subshapes,
            removedSubshapeIDs: removedSubshapeIDs,
            lineage: lineage
        )
    }

    private func error(
        _ code: KernelErrorCode,
        featureID: FeatureID? = nil,
        tolerance: ModelingTolerance,
        _ message: String
    ) -> KernelError {
        KernelError(
            phase: code == .topologyFailure ? .topology : .evaluation,
            code: code,
            featureID: featureID,
            tolerance: tolerance,
            message: message
        )
    }
}
