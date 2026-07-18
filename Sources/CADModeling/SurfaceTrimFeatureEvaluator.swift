import CADCore
import CADIR
import CADTopology

public struct SurfaceTrimFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    private let editor: any RectangularPlanarSheetEditing
    private let identityBuilder: any CarriedTopologyIdentityBuilding
    private let geometryRebuilder: any PlanarBodyGeometryRebuilding

    public init() {
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
        guard case let .surfaceTrim(trim) = feature.operation else {
            throw kernelError(.invalidInput, featureID: feature.id, tolerance: context.tolerance, "Surface trim evaluator requires a surfaceTrim feature.")
        }
        try FeatureEvaluationBoundary.validateRequest(featureID: feature.id, tolerance: context.tolerance) {
            try trim.validate(tolerance: context.tolerance)
        }
        try FeatureEvaluationBoundary.validateExactInput(
            context.brep,
            featureID: feature.id,
            tolerance: context.tolerance
        )
        guard case let .closed(lowerU, upperU) = trim.uDomain,
              case let .closed(lowerV, upperV) = trim.vDomain else {
            throw kernelError(.invalidInput, featureID: feature.id, tolerance: context.tolerance, "Surface trim domains must be finite.")
        }
        let bodyID = try targetBodyID(trim.target.featureID, featureID: feature.id, context: context)
        let replacedSubshapeIDs = try BodyTopologyScope(
            bodyID: bodyID,
            model: context.brep
        ).subshapeIDs(in: context.subshapes)
        var model = context.brep
        let current = try editor.bounds(bodyID: bodyID, model: model, tolerance: context.tolerance)
        guard lowerU >= current.lowerU - context.tolerance.distance,
              upperU <= current.upperU + context.tolerance.distance,
              lowerV >= current.lowerV - context.tolerance.distance,
              upperV <= current.upperV + context.tolerance.distance else {
            throw kernelError(
                .invalidInput,
                featureID: feature.id,
                tolerance: context.tolerance,
                "Surface trim domains must be contained in the current sheet bounds."
            )
        }
        try editor.resize(
            bodyID: bodyID,
            to: PlanarSheetParameterBounds(lowerU: lowerU, upperU: upperU, lowerV: lowerV, upperV: upperV),
            model: &model,
            tolerance: context.tolerance
        )
        return try result(
            featureID: feature.id,
            bodyID: bodyID,
            replacedSubshapeIDs: replacedSubshapeIDs,
            model: &model,
            context: context
        )
    }

    private func result(
        featureID: FeatureID,
        bodyID: BodyID,
        replacedSubshapeIDs: Set<SubshapeID>,
        model: inout BRepModel,
        context: EvaluationContext
    ) throws -> EvaluationResult {
        try geometryRebuilder.rebuild(
            featureID: featureID,
            bodyID: bodyID,
            in: &model,
            tolerance: context.tolerance
        )
        try ExactFacePcurveBuilder().populateMissingPcurves(in: &model, tolerance: context.tolerance)
        try model.validate(level: .exact, tolerance: context.tolerance)
        let identity = try identityBuilder.identity(featureID: featureID, bodyID: bodyID, model: model, context: context)
        return EvaluationResult(
            brep: model,
            subshapes: identity.subshapes,
            removedSubshapeIDs: replacedSubshapeIDs,
            lineage: identity.lineage
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
        KernelError(phase: .evaluation, code: code, featureID: featureID, tolerance: tolerance, message: message)
    }
}
