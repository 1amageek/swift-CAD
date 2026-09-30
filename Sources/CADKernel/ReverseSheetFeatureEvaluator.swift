import CADCore
import CADIR
import CADModeling
import CADTopology

/// Turns a sheet over in its place (`ReverseSheetFeature`). The sheet's exact faces are copied as
/// sewing patches, each turned to the opposite side (its loops traversed the other way), and
/// sewn back in the sheet's own shells, so every face keeps its surface and trim and only its
/// side changes. The source body and every subshape of it are removed; each new face's lineage
/// leads to the face it turns over.
struct ReverseSheetFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    func evaluate(feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult {
        try evaluateValidated(feature: feature, context: context).result
    }

    func evaluateValidated(feature: FeatureNode, context: EvaluationContext) throws -> ValidatedFeatureEvaluation {
        try FeatureEvaluationBoundary.evaluateValidated(featureID: feature.id, tolerance: context.tolerance) {
            try reverse(feature: feature, context: context)
        }
    }

    private func reverse(feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult {
        guard case let .reverseSheet(reverse) = feature.operation else {
            throw error(.invalidInput, feature.id, context, "Reverse sheet evaluator requires a reverseSheet feature.")
        }
        try FeatureEvaluationBoundary.validateRequest(featureID: feature.id, tolerance: context.tolerance) {
            try reverse.validate()
        }
        try FeatureEvaluationBoundary.validateExactInput(context, featureID: feature.id, tolerance: context.tolerance)
        let tolerance = context.tolerance
        let sourceBodyID = try context.bodyID(generatedBy: reverse.target.featureID)
        guard let body = context.brep.bodies[sourceBodyID] else {
            throw error(.missingReference, feature.id, context, "Reverse sheet source body is missing.")
        }
        guard body.kind == .sheet else {
            throw error(.invalidInput, feature.id, context, "Reverse turns a sheet over; a solid's faces face out of it.")
        }
        let extraction = try DefaultBRepFacePatchExtractor().extract(
            bodyID: sourceBodyID,
            featureID: feature.id,
            from: context.brep,
            sourceSubshapes: context.subshapes.entries,
            tolerance: tolerance
        )
        let adapter = BRepSewingPatchOrientationAdapter()
        let shells = try extraction.request.shells.map { shell in
            BRepSewingShell(
                stableID: shell.stableID,
                patches: try shell.patches.map {
                    try adapter.reorient($0, to: $0.orientation == .forward ? .reversed : .forward, tolerance: tolerance)
                },
                orientation: shell.orientation
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
