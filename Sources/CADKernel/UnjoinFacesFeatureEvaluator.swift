import CADCore
import CADIR
import CADModeling
import CADTopology

/// Separates a body's faces into the shells of one sheet body that takes the body's place
/// (`UnjoinFacesFeature`). The source's exact faces are copied as sewing patches; each chosen
/// face is sewn as a shell of its own and the faces left are partitioned into the shells they
/// still form, so every face keeps its geometry, trim and side. The source body and every
/// subshape of it are removed; each new face's lineage leads to the face it separates.
struct UnjoinFacesFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    private let subshapeResolver: any StableSubshapeResolving

    init(subshapeResolver: any StableSubshapeResolving = StableSubshapeResolver()) {
        self.subshapeResolver = subshapeResolver
    }

    func evaluate(feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult {
        try evaluateValidated(feature: feature, context: context).result
    }

    func evaluateValidated(feature: FeatureNode, context: EvaluationContext) throws -> ValidatedFeatureEvaluation {
        try FeatureEvaluationBoundary.evaluateValidated(featureID: feature.id, tolerance: context.tolerance) {
            try unjoin(feature: feature, context: context)
        }
    }

    private func unjoin(feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult {
        guard case let .unjoinFaces(unjoin) = feature.operation else {
            throw error(.invalidInput, feature.id, context, "Unjoin faces evaluator requires an unjoinFaces feature.")
        }
        try FeatureEvaluationBoundary.validateRequest(featureID: feature.id, tolerance: context.tolerance) {
            try unjoin.validate()
        }
        try FeatureEvaluationBoundary.validateExactInput(context, featureID: feature.id, tolerance: context.tolerance)
        let tolerance = context.tolerance
        let sourceBodyID = try context.bodyID(generatedBy: unjoin.target.featureID)
        guard let body = context.brep.bodies[sourceBodyID] else {
            throw error(.missingReference, feature.id, context, "Unjoin faces source body is missing.")
        }
        let extraction = try DefaultBRepFacePatchExtractor().extract(
            bodyID: sourceBodyID,
            featureID: feature.id,
            from: context.brep,
            sourceSubshapes: context.subshapes.entries,
            tolerance: tolerance
        )
        let patches = extraction.request.shells.flatMap(\.patches)
        let separated: Set<String> = switch unjoin.selection {
        case .everyFace:
            Set(patches.map(\.stableID))
        case let .faces(references):
            try ExtractFaceSet(
                references: references, body: body, model: context.brep, subshapes: context.subshapes,
                lineage: context.lineage, resolver: subshapeResolver, tolerance: tolerance
            ).patchStableIDs
        }
        var shells = patches.filter { separated.contains($0.stableID) }.map {
            BRepSewingShell(stableID: "unjoin:face:\($0.stableID)", patches: [$0])
        }
        let remaining = patches.filter { separated.contains($0.stableID) == false }
        if remaining.isEmpty == false {
            shells += try BRepSewingPatchShellPartitioner().shells(
                patches: remaining,
                stablePrefix: "unjoin:rest",
                tolerance: tolerance
            )
        }
        let sewn = try DefaultBRepSewer().sew(
            BRepSewingRequest(featureID: feature.id, bodyKind: .sheet, shells: shells),
            tolerance: tolerance
        )
        // Sewing rebuilds every face, edge and vertex, so every subshape of the source goes.
        let removedSubshapeIDs = try BodyTopologyScope(bodyID: sourceBodyID, model: context.brep)
            .subshapeIDs(in: context.subshapes)
            .union(context.subshapes.entries.filter { $0.value == .body(sourceBodyID) }.map(\.key))
        let model = try BRepBodyModelReplacer().replacing(
            bodyIDs: [sourceBodyID],
            with: sewn.brep,
            in: context.brep
        )
        return EvaluationResult(
            brep: model,
            subshapes: sewn.subshapes,
            removedSubshapeIDs: removedSubshapeIDs,
            lineage: sewn.lineage
        )
    }

    private func error(_ code: KernelErrorCode, _ featureID: FeatureID, _ context: EvaluationContext, _ message: String) -> KernelError {
        KernelError(phase: .evaluation, code: code, featureID: featureID, tolerance: context.tolerance, message: message)
    }
}
