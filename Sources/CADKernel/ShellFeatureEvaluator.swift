import Foundation
import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology

/// Hollow: a solid emptied to walls `thickness` thick inside it. With faces chosen, the void
/// opens through them; with none, it is closed inside the solid.
///
/// An inner copy of the solid, sewn in an unpublished stage, has every face pushed inward by the
/// thickness and each opened face pushed outward by it, so the copy reaches through the openings
/// (`FaceSurfaceReplacementRebuilder`); the solid less the copy is the hollow (`BooleanPipeline`).
/// A thickness a face cannot be pushed in by — a round narrower than it, a wall it passes — is
/// refused.
public struct ShellFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    private let sewer: any BRepSewing
    private let resolver: ParameterResolving
    private let subshapeResolver: any StableSubshapeResolving

    public init(
        sewer: any BRepSewing = DefaultBRepSewer(),
        resolver: ParameterResolving = ParameterResolver(),
        subshapeResolver: any StableSubshapeResolving = StableSubshapeResolver()
    ) {
        self.sewer = sewer
        self.resolver = resolver
        self.subshapeResolver = subshapeResolver
    }

    public func evaluate(feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult {
        try evaluateValidated(feature: feature, context: context).result
    }

    package func evaluateValidated(feature: FeatureNode, context: EvaluationContext) throws -> ValidatedFeatureEvaluation {
        try FeatureEvaluationBoundary.evaluateValidated(featureID: feature.id, tolerance: context.tolerance) {
            try evaluateHollow(feature: feature, context: context)
        }
    }

    private func evaluateHollow(feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult {
        guard case let .shell(shell) = feature.operation else {
            throw failure(.invalidInput, feature.id, context.tolerance, "Shell evaluator requires a shell feature.")
        }
        try FeatureEvaluationBoundary.validateRequest(featureID: feature.id, tolerance: context.tolerance) {
            try shell.validate()
        }
        try FeatureEvaluationBoundary.validateExactInput(context, featureID: feature.id, tolerance: context.tolerance)
        let tolerance = context.tolerance
        let quantity = try resolver.evaluate(shell.thickness, parameters: context.parameters, variables: [:])
        guard quantity.kind == .length, quantity.value.isFinite, quantity.value > tolerance.distance else {
            throw failure(.invalidInput, feature.id, tolerance, "Shell thickness must be a positive length.")
        }
        let thickness = quantity.value
        let bodyID = try context.bodyID(generatedBy: shell.target.featureID)
        guard context.brep.bodies[bodyID]?.kind == .solid else {
            throw failure(.unsupportedCapability, feature.id, tolerance, "Shell hollows a solid.")
        }
        let scope = try BodyTopologyScope(bodyID: bodyID, model: context.brep)
        var opened = Set<FaceID>()
        for reference in shell.removedFaces {
            let resolved = try subshapeResolver.topologyReference(
                for: reference, model: context.brep, subshapes: context.subshapes, lineage: context.lineage, tolerance: tolerance
            )
            guard case let .face(faceID) = resolved, scope.references.contains(.face(faceID)) else {
                throw KernelError(
                    phase: .evaluation, code: .missingReference, featureID: feature.id, subshapeID: reference.subshapeID,
                    tolerance: tolerance, message: "Shell removal face must belong to the target body."
                )
            }
            guard opened.insert(faceID).inserted else {
                throw failure(.invalidInput, feature.id, tolerance, "Shell removal faces resolve to the same face.")
            }
        }

        // The inner copy, sewn from the solid's own faces in an unpublished stage.
        let stageID = featureEvaluationStageID(featureID: feature.id, domain: .hollowInnerBody, ordinal: 0)
        let extraction = try DefaultBRepFacePatchExtractor().extract(
            bodyID: bodyID, featureID: stageID, from: context.brep, sourceSubshapes: context.subshapes.entries, tolerance: tolerance
        )
        let copy = try sewer.sew(
            BRepSewingRequest(featureID: stageID, bodyKind: .solid, shells: extraction.request.shells), tolerance: tolerance
        )
        guard let copyBodyID = copy.brep.bodies.keys.first, copy.brep.bodies.count == 1 else {
            throw failure(.topologyFailure, feature.id, tolerance, "The solid's inner copy did not sew into one solid.")
        }
        // Each copied face traces to the solid's face it copies.
        var sourceFace: [FaceID: FaceID] = [:]
        for (subshapeID, reference) in copy.subshapes {
            guard case let .face(copyFace) = reference else { continue }
            for parent in copy.lineage[subshapeID]?.parents ?? [] {
                if case let .face(source)? = context.subshapes[parent] { sourceFace[copyFace] = source }
            }
        }
        var model = try BRepModelCombiner().combined([context.brep, copy.brep])
        let copyScope = try BodyTopologyScope(bodyID: copyBodyID, model: model)
        var replacements: [FaceID: FaceSurfaceReplacementRebuilder.Replacement] = [:]
        for case let .face(copyFace) in copyScope.references {
            guard let face = model.faces[copyFace], let surface = model.geometry.surfaces[face.surfaceID] else {
                throw TopologyError.missingReference("A face of the solid's inner copy is missing.")
            }
            guard let source = sourceFace[copyFace] else {
                throw failure(.topologyFailure, feature.id, tolerance, "A face of the solid's inner copy does not trace to the solid.")
            }
            // Walls move in; an opened face moves out, so the copy reaches through the opening.
            let distance = opened.contains(source) ? thickness : -thickness
            replacements[copyFace] = FaceSurfaceReplacementRebuilder.Replacement(
                surface: try FaceSurfaceOffsetter().offset(surface, orientation: face.orientation, by: distance, tolerance: tolerance),
                orientation: face.orientation
            )
        }
        try FaceSurfaceReplacementRebuilder().replace(replacements, bodyID: copyBodyID, featureID: feature.id, model: &model, tolerance: tolerance)
        try ExactFacePcurveBuilder().populateMissingPcurves(in: &model, tolerance: tolerance)
        try BRepBodySubmodelExtractor().extract(bodyIDs: [copyBodyID], from: model).validate(level: .volumetric, tolerance: tolerance)
        return try BooleanPipeline(evaluator: ExactBRepBooleanEvaluator()).evaluate(
            operation: .difference,
            targetBodyIDs: [bodyID],
            toolBodyID: copyBodyID,
            keepTools: false,
            featureID: feature.id,
            model: model,
            subshapes: context.subshapes.entries,
            toolSubshapes: copy.subshapes,
            inputLineage: context.lineage,
            tolerance: tolerance
        )
    }

    private func failure(_ code: KernelErrorCode, _ featureID: FeatureID, _ tolerance: ModelingTolerance, _ message: String) -> KernelError {
        KernelError(phase: code == .topologyFailure ? .topology : .evaluation, code: code, featureID: featureID, tolerance: tolerance, message: message)
    }
}
