import CADCore
import CADIR

public struct SurfaceExtendFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    private let resolver: ParameterResolving
    private let editor: any RectangularPlanarSheetEditing
    private let identityBuilder: any CarriedTopologyIdentityBuilding
    private let geometryRebuilder: any PlanarBodyGeometryRebuilding

    public init(resolver: ParameterResolving = ParameterResolver()) {
        self.resolver = resolver
        self.editor = DefaultRectangularPlanarSheetEditor()
        self.identityBuilder = DefaultCarriedTopologyIdentityBuilder()
        self.geometryRebuilder = DefaultPlanarBodyGeometryRebuilder()
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
        guard case let .surfaceExtend(extensionRequest) = feature.operation else {
            throw kernelError(.invalidInput, featureID: feature.id, tolerance: context.tolerance, "Surface extend evaluator requires a surfaceExtend feature.")
        }
        try FeatureEvaluationBoundary.validateRequest(featureID: feature.id, tolerance: context.tolerance) {
            try extensionRequest.validate()
        }
        try FeatureEvaluationBoundary.validateExactInput(
            context.brep,
            featureID: feature.id,
            tolerance: context.tolerance
        )
        let distances = try resolvedDistances(extensionRequest.distances, featureID: feature.id, context: context)
        let bodyID = try targetBodyID(extensionRequest.target.featureID, featureID: feature.id, context: context)
        let replacedSubshapeIDs = try BodyTopologyScope(
            bodyID: bodyID,
            model: context.brep
        ).subshapeIDs(in: context.subshapes)
        var model = context.brep
        let current = try editor.bounds(bodyID: bodyID, model: model, tolerance: context.tolerance)
        try editor.resize(
            bodyID: bodyID,
            to: PlanarSheetParameterBounds(
                lowerU: current.lowerU - distances.lowerU,
                upperU: current.upperU + distances.upperU,
                lowerV: current.lowerV - distances.lowerV,
                upperV: current.upperV + distances.upperV
            ),
            model: &model,
            tolerance: context.tolerance
        )
        try geometryRebuilder.rebuild(
            featureID: feature.id,
            bodyID: bodyID,
            in: &model,
            tolerance: context.tolerance
        )
        try ExactFacePcurveBuilder().populateMissingPcurves(in: &model, tolerance: context.tolerance)
        try model.validate(level: .exact, tolerance: context.tolerance)
        let identity = try identityBuilder.identity(featureID: feature.id, bodyID: bodyID, model: model, context: context)
        return EvaluationResult(
            brep: model,
            subshapes: identity.subshapes,
            removedSubshapeIDs: replacedSubshapeIDs,
            lineage: identity.lineage
        )
    }

    private func resolvedDistances(
        _ expressions: SurfaceExtensionDistances,
        featureID: FeatureID,
        context: EvaluationContext
    ) throws -> PlanarSheetParameterBounds {
        let values = try [
            expressions.lowerU,
            expressions.upperU,
            expressions.lowerV,
            expressions.upperV,
        ].map { expression -> Double in
            let quantity = try resolver.evaluate(expression, parameters: context.parameters, variables: [:])
            guard quantity.kind == .length else {
                throw UnitError.expectedQuantity(operation: "surfaceExtend.distance", expected: .length, actual: quantity.kind)
            }
            guard quantity.value.isFinite, quantity.value >= 0.0 else {
                throw kernelError(.invalidInput, featureID: featureID, tolerance: context.tolerance, "Surface extension distances must be finite and nonnegative.")
            }
            return quantity.value
        }
        guard values.contains(where: { $0 > context.tolerance.distance }) else {
            throw kernelError(.invalidInput, featureID: featureID, tolerance: context.tolerance, "At least one surface extension distance must exceed modeling tolerance.")
        }
        return PlanarSheetParameterBounds(lowerU: values[0], upperU: values[1], lowerV: values[2], upperV: values[3])
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
        KernelError(phase: .evaluation, code: code, featureID: featureID, tolerance: tolerance, message: message)
    }
}
