import Foundation
import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology

/// Hollow: a solid walled `thickness` thick, inside it when the thickness is negative and outside
/// it (the solid itself the cavity) when positive, as Plasticity's sign. With faces chosen, the
/// cavity opens through them; with none, it is closed.
///
/// Inward, an inner copy of the solid, sewn in an unpublished stage, has every face pushed inward
/// by the thickness and each opened face pushed outward by it, so the copy reaches through the
/// openings (`FaceSurfaceReplacementRebuilder`); the solid less the copy is the hollow
/// (`BooleanPipeline`). Outward, an outer copy has every face but the opened ones pushed outward,
/// a second copy only the opened ones, and the outer less the second replaces the solid. A
/// thickness a face cannot be pushed by — a round narrower than it, a wall it passes — is refused.
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
        guard quantity.kind == .length, quantity.value.isFinite, abs(quantity.value) > tolerance.distance else {
            throw failure(.invalidInput, feature.id, tolerance, "Shell thickness must be a nonzero length.")
        }
        let thickness = abs(quantity.value)
        let outward = quantity.value > 0
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

        // A copy of the solid sewn from its own faces in an unpublished stage, each face moved by
        // `distance(source face)` along its outward side.
        func movedCopy(ordinal: UInt64, model: inout BRepModel, distance: (FaceID) -> Double)
            throws -> (bodyID: BodyID, subshapes: [SubshapeID: TopologyReference], lineage: [SubshapeID: TopologyLineage]) {
            let stageID = featureEvaluationStageID(featureID: feature.id, domain: .hollowInnerBody, ordinal: ordinal)
            let extraction = try DefaultBRepFacePatchExtractor().extract(
                bodyID: bodyID, featureID: stageID, from: context.brep, sourceSubshapes: context.subshapes.entries, tolerance: tolerance
            )
            let copy = try sewer.sew(
                BRepSewingRequest(featureID: stageID, bodyKind: .solid, shells: extraction.request.shells), tolerance: tolerance
            )
            guard let copyBodyID = copy.brep.bodies.keys.first, copy.brep.bodies.count == 1 else {
                throw failure(.topologyFailure, feature.id, tolerance, "The solid's copy did not sew into one solid.")
            }
            // Each copied face traces to the solid's face it copies.
            var sourceFace: [FaceID: FaceID] = [:]
            for (subshapeID, reference) in copy.subshapes {
                guard case let .face(copyFace) = reference else { continue }
                for parent in copy.lineage[subshapeID]?.parents ?? [] {
                    if case let .face(source)? = context.subshapes[parent] { sourceFace[copyFace] = source }
                }
            }
            model = try BRepModelCombiner().combined([model, copy.brep])
            let copyScope = try BodyTopologyScope(bodyID: copyBodyID, model: model)
            var replacements: [FaceID: FaceSurfaceReplacementRebuilder.Replacement] = [:]
            for case let .face(copyFace) in copyScope.references {
                guard let face = model.faces[copyFace], let surface = model.geometry.surfaces[face.surfaceID] else {
                    throw TopologyError.missingReference("A face of the solid's copy is missing.")
                }
                guard let source = sourceFace[copyFace] else {
                    throw failure(.topologyFailure, feature.id, tolerance, "A face of the solid's copy does not trace to the solid.")
                }
                let moved = distance(source)
                guard moved != 0 else { continue }
                replacements[copyFace] = FaceSurfaceReplacementRebuilder.Replacement(
                    surface: try FaceSurfaceOffsetter().offset(surface, orientation: face.orientation, by: moved, tolerance: tolerance),
                    orientation: face.orientation
                )
            }
            if replacements.isEmpty == false {
                try FaceSurfaceReplacementRebuilder().replace(replacements, bodyID: copyBodyID, featureID: feature.id, model: &model, tolerance: tolerance)
                try ExactFacePcurveBuilder().populateMissingPcurves(in: &model, tolerance: tolerance)
            }
            try BRepBodySubmodelExtractor().extract(bodyIDs: [copyBodyID], from: model).validate(level: .volumetric, tolerance: tolerance)
            return (copyBodyID, copy.subshapes, copy.lineage)
        }

        var model = context.brep
        guard outward else {
            // Walls move in; an opened face moves out, so the copy reaches through the opening.
            let inner = try movedCopy(ordinal: 0, model: &model) { opened.contains($0) ? thickness : -thickness }
            return try BooleanPipeline(evaluator: ExactBRepBooleanEvaluator()).evaluate(
                operation: .difference,
                targetBodyIDs: [bodyID],
                toolBodyID: inner.bodyID,
                keepTools: false,
                featureID: feature.id,
                model: model,
                subshapes: context.subshapes.entries,
                toolSubshapes: inner.subshapes,
                inputLineage: context.lineage,
                tolerance: tolerance
            )
        }
        // Outward: the outer copy's walls move out, its opened faces stay; the cavity is the solid
        // with its opened faces moved out, so it reaches through the outer copy's openings.
        let outer = try movedCopy(ordinal: 1, model: &model) { opened.contains($0) ? 0 : thickness }
        let cavity = try movedCopy(ordinal: 2, model: &model) { opened.contains($0) ? thickness : 0 }
        var result = try BooleanPipeline(evaluator: ExactBRepBooleanEvaluator()).evaluate(
            operation: .difference,
            targetBodyIDs: [outer.bodyID],
            toolBodyID: cavity.bodyID,
            keepTools: false,
            featureID: feature.id,
            model: model,
            subshapes: outer.subshapes,
            toolSubshapes: cavity.subshapes,
            inputLineage: context.lineage.merging(outer.lineage) { current, _ in current }.merging(cavity.lineage) { current, _ in current },
            tolerance: tolerance
        )
        // The walled body replaces the solid, its faces tracing through the copies to the solid's.
        result.brep = try BRepBodySubmodelExtractor().extract(bodyIDs: Set(result.brep.bodies.keys).subtracting([bodyID]), from: result.brep)
        result.removedSubshapeIDs.formUnion(scope.subshapeIDs(in: context.subshapes))
        result.lineage = composed(result.lineage, through: outer.lineage.merging(cavity.lineage) { current, _ in current })
        result.validatedBRep = nil
        return result
    }

    /// `lineage` with each parent that is a stage copy's subshape replaced by the parents it was
    /// copied from, the relation following the parents left.
    private func composed(_ lineage: [SubshapeID: TopologyLineage], through stages: [SubshapeID: TopologyLineage]) -> [SubshapeID: TopologyLineage] {
        lineage.mapValues { entry in
            let parents = Set(entry.parents.flatMap { parent in stages[parent].map(\.parents) ?? [parent] })
            let relation: TopologyLineageRelation = switch parents.count {
            case 0: .generated
            case 1: entry.relation == .merged || entry.relation == .generated ? .preserved : entry.relation
            default: .merged
            }
            return TopologyLineage(output: entry.output, parents: Array(parents), relation: relation)
        }
    }

    private func failure(_ code: KernelErrorCode, _ featureID: FeatureID, _ tolerance: ModelingTolerance, _ message: String) -> KernelError {
        KernelError(phase: code == .topologyFailure ? .topology : .evaluation, code: code, featureID: featureID, tolerance: tolerance, message: message)
    }
}
