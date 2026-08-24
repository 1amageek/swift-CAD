import CADCore
import CADGeometry
import CADIR
import CADTopology

public struct ThickenFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    private let resolver: ParameterResolving
    private let sewer: any BRepSewing

    public init(
        sewer: any BRepSewing,
        resolver: ParameterResolving = ParameterResolver()
    ) {
        self.resolver = resolver
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
        guard case let .thicken(thicken) = feature.operation else {
            throw kernelError(.invalidInput, featureID: feature.id, tolerance: context.tolerance, "Thicken evaluator requires a thicken feature.")
        }
        let quantity = try resolver.evaluate(thicken.thickness, parameters: context.parameters, variables: [:])
        guard quantity.kind == .length,
              quantity.value.isFinite,
              quantity.value > context.tolerance.distance else {
            throw kernelError(.invalidInput, featureID: feature.id, tolerance: context.tolerance, "Thicken thickness must be a positive length above modeling tolerance.")
        }
        let bodyID = try targetBodyID(thicken.target.featureID, featureID: feature.id, context: context)
        let replacedSubshapeIDs = try BodyTopologyScope(
            bodyID: bodyID,
            model: context.brep
        ).subshapeIDs(in: context.subshapes)
        let request = try ExactThickenRequestBuilder().request(
            featureID: feature.id,
            bodyID: bodyID,
            thickness: quantity.value,
            side: thicken.side,
            model: context.brep,
            subshapes: context.subshapes,
            tolerance: context.tolerance
        )
        let result = try sewer.sew(request, tolerance: context.tolerance)
        let model = try BRepBodyModelReplacer().replacing(
            bodyID: bodyID,
            with: result.bodyID,
            from: result.brep,
            in: context.brep
        )
        try model.validate(level: .volumetric, tolerance: context.tolerance)
        return EvaluationResult(
            brep: model,
            subshapes: result.subshapes,
            removedSubshapeIDs: replacedSubshapeIDs,
            lineage: result.lineage
        )
    }

    private func targetBodyID(
        _ sourceFeatureID: FeatureID,
        featureID: FeatureID,
        context: EvaluationContext
    ) throws -> BodyID {
        try context.bodyID(generatedBy: sourceFeatureID)
    }

    private func kernelError(
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
