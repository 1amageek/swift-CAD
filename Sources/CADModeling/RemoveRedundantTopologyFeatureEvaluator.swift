import Foundation
import CADCore
import CADGeometry
import CADIR
import CADTopology

/// Delete Redundant Topology on a solid or a sheet (`RedundantTopologyRemover`).
public struct RemoveRedundantTopologyFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    private let identityBuilder: any CarriedTopologyIdentityBuilding

    public init() {
        identityBuilder = DefaultCarriedTopologyIdentityBuilder()
    }

    public func evaluate(feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult {
        try evaluateValidated(feature: feature, context: context).result
    }

    package func evaluateValidated(feature: FeatureNode, context: EvaluationContext) throws -> ValidatedFeatureEvaluation {
        try FeatureEvaluationBoundary.evaluateValidated(featureID: feature.id, tolerance: context.tolerance) {
            try evaluateRemoval(feature: feature, context: context)
        }
    }

    private func evaluateRemoval(feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult {
        guard case let .removeRedundantTopology(removal) = feature.operation else {
            throw failure(.invalidInput, feature.id, context.tolerance, "Delete Redundant Topology evaluator requires a removeRedundantTopology feature.")
        }
        try FeatureEvaluationBoundary.validateRequest(featureID: feature.id, tolerance: context.tolerance) {
            try removal.validate()
        }
        try FeatureEvaluationBoundary.validateExactInput(context, featureID: feature.id, tolerance: context.tolerance)
        let tolerance = context.tolerance
        let bodyID = try context.bodyID(generatedBy: removal.target.featureID)
        let scope = try BodyTopologyScope(bodyID: bodyID, model: context.brep)
        var model = context.brep
        guard try RedundantTopologyRemover().remove(bodyID: bodyID, featureID: feature.id, model: &model, tolerance: tolerance) else {
            throw failure(.invalidInput, feature.id, tolerance, "The body has no redundant faces, edges or vertices.")
        }
        try ExactFacePcurveBuilder().populateMissingPcurves(in: &model, tolerance: tolerance)
        let isSolid = model.bodies[bodyID]?.kind == .solid
        try model.validate(level: isSolid ? .volumetric : .exact, tolerance: tolerance)
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
