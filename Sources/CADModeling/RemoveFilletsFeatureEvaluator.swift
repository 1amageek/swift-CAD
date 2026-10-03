import Foundation
import CADCore
import CADGeometry
import CADIR
import CADTopology

/// Remove Fillets From Shell: the solid's fillets within the radius and convexity asked for
/// (`FaceRemovalPlanner.fillets`) collapse onto the faces they joined (`FaceRemovalHealer`).
public struct RemoveFilletsFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    private let resolver: ParameterResolving
    private let identityBuilder: any CarriedTopologyIdentityBuilding

    public init(resolver: ParameterResolving = ParameterResolver()) {
        self.resolver = resolver
        identityBuilder = DefaultCarriedTopologyIdentityBuilder()
    }

    public func evaluate(feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult {
        try evaluateValidated(feature: feature, context: context).result
    }

    package func evaluateValidated(feature: FeatureNode, context: EvaluationContext) throws -> ValidatedFeatureEvaluation {
        try FeatureEvaluationBoundary.evaluateValidated(featureID: feature.id, tolerance: context.tolerance) {
            try evaluateRemoveFillets(feature: feature, context: context)
        }
    }

    private func evaluateRemoveFillets(feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult {
        guard case let .removeFillets(removal) = feature.operation else {
            throw failure(.invalidInput, feature.id, context.tolerance, "Remove Fillets evaluator requires a removeFillets feature.")
        }
        try FeatureEvaluationBoundary.validateRequest(featureID: feature.id, tolerance: context.tolerance) {
            try removal.validate()
        }
        try FeatureEvaluationBoundary.validateExactInput(context, featureID: feature.id, tolerance: context.tolerance)
        let tolerance = context.tolerance
        var maximumRadius: Double?
        if let expression = removal.maximumRadius {
            let quantity = try resolver.evaluate(expression, parameters: context.parameters, variables: [:])
            guard quantity.kind == .length, quantity.value.isFinite, quantity.value > tolerance.distance else {
                throw failure(.invalidInput, feature.id, tolerance, "Remove Fillets maximum radius must be a positive length.")
            }
            maximumRadius = quantity.value
        }
        let bodyID = try context.bodyID(generatedBy: removal.target.featureID)
        guard let bodyKind = context.brep.bodies[bodyID]?.kind else {
            throw failure(.missingReference, feature.id, tolerance, "Remove Fillets' body is missing.")
        }
        let scope = try BodyTopologyScope(bodyID: bodyID, model: context.brep)
        let convexity: FaceRemovalPlanner.Convexity = switch removal.convexity {
        case .any: .any
        case .convex: .convex
        case .concave: .concave
        }
        let plan = try FaceRemovalPlanner().fillets(
            of: bodyID, maximumRadius: maximumRadius, convexity: convexity, model: context.brep, tolerance: tolerance
        )
        guard plan.isEmpty == false else {
            throw failure(.invalidInput, feature.id, tolerance, "The solid has no fillets within the radius and convexity asked for.")
        }
        var model = context.brep
        try FaceRemovalHealer().heal(plan, bodyID: bodyID, featureID: feature.id, model: &model, tolerance: tolerance)
        try ExactFacePcurveBuilder().populateMissingPcurves(in: &model, tolerance: tolerance)
        // A sheet heals open: its rounds' open ends close up with the faces beside them.
        try model.validate(level: bodyKind == .solid ? .volumetric : .exact, tolerance: tolerance)
        let identity = try identityBuilder.identity(featureID: feature.id, bodyID: bodyID, model: model, context: context)
        return EvaluationResult(
            brep: model,
            subshapes: identity.subshapes,
            removedSubshapeIDs: scope.subshapeIDs(in: context.subshapes),
            lineage: identity.lineage
        )
    }

    private func failure(_ code: KernelErrorCode, _ featureID: FeatureID, _ tolerance: ModelingTolerance, _ message: String) -> KernelError {
        KernelError(phase: code == .topologyFailure ? .topology : .evaluation, code: code, featureID: featureID, tolerance: tolerance, message: message)
    }
}
