import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology

/// Imprints where a tool crosses a target (`ImprintBodyFeature`): the exact Boolean intersection
/// of the two bodies' faces, clipped to both faces, gives the curves on the target's faces
/// (`BooleanPipeline`), which `BRepFaceImprinter` splits the target along. The tool is read, not
/// changed. Faces that touch without crossing add nothing.
struct ImprintBodyFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    private let pipeline: BooleanPipeline

    init(pipeline: BooleanPipeline = BooleanPipeline(evaluator: ExactBRepBooleanEvaluator())) {
        self.pipeline = pipeline
    }

    func evaluate(feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult {
        try evaluateValidated(feature: feature, context: context).result
    }

    func evaluateValidated(feature: FeatureNode, context: EvaluationContext) throws -> ValidatedFeatureEvaluation {
        try FeatureEvaluationBoundary.evaluateValidated(featureID: feature.id, tolerance: context.tolerance) {
            try imprint(feature: feature, context: context)
        }
    }

    private func imprint(feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult {
        guard case let .imprintBody(imprint) = feature.operation else {
            throw failure(.invalidInput, feature.id, context, "Imprint evaluator requires an imprintBody feature.")
        }
        try FeatureEvaluationBoundary.validateRequest(featureID: feature.id, tolerance: context.tolerance) {
            try imprint.validate()
        }
        try FeatureEvaluationBoundary.validateExactInput(context, featureID: feature.id, tolerance: context.tolerance)
        let targetBodyID = try context.bodyID(generatedBy: imprint.target.featureID)
        let toolBodyID = try context.bodyID(generatedBy: imprint.tool.featureID)
        let curves = try Self.crossings(
            of: targetBodyID, by: toolBodyID, pipeline: pipeline, featureID: feature.id, context: context
        )
        guard curves.isEmpty == false else {
            throw failure(.invalidInput, feature.id, context, "The tool does not cross the target.")
        }
        let completed = try BRepImprintCompletion().completed(
            curves, by: imprint.completion, model: context.brep, sourceSubshapes: context.subshapes.entries, tolerance: context.tolerance
        )
        return try BRepFaceImprinter().imprint(completed, on: targetBodyID, featureID: feature.id, context: context)
    }

    /// The curves where the tool's faces cross the target's, each on the target face it lies on.
    static func crossings(
        of targetBodyID: BodyID,
        by toolBodyID: BodyID,
        pipeline: BooleanPipeline,
        featureID: FeatureID,
        context: EvaluationContext
    ) throws -> [BRepFaceImprinter.Curve] {
        try crossingPairs(of: targetBodyID, by: toolBodyID, pipeline: pipeline, featureID: featureID, context: context).map(\.onTarget)
    }

    /// Each crossing both as a curve on the target face and as the same curve on the tool face.
    static func crossingPairs(
        of targetBodyID: BodyID,
        by toolBodyID: BodyID,
        pipeline: BooleanPipeline,
        featureID: FeatureID,
        context: EvaluationContext
    ) throws -> [(onTarget: BRepFaceImprinter.Curve, onTool: BRepSewingEdge)] {
        let tolerance = context.tolerance
        let intersections = try pipeline.completeIntersectionGraph(
            targetBodyIDs: [targetBodyID], toolBodyID: toolBodyID, operation: .region, model: context.brep, tolerance: tolerance
        )
        let splits = try pipeline.uvSplitGraph(intersectionGraph: intersections, model: context.brep, tolerance: tolerance)
        var pairs: [(onTarget: BRepFaceImprinter.Curve, onTool: BRepSewingEdge)] = []
        for split in splits.splits {
            let faceID = split.facePair.targetFaceID
            let parents = context.subshapeIDs(for: .face(faceID)) + context.subshapeIDs(for: .face(split.facePair.toolFaceID))
            for component in split.components {
                switch component.geometry {
                case .tangent:
                    continue
                case .coincident:
                    // FIXME(INCOMPLETE_IMPLEMENTATION): A tool face lying on a target face (a sheet
                    // laid on a face) should imprint the tool face's outline where it lies on the
                    // target face. Imprint Body Body, and Imprint Curve Body through its projection
                    // sheet, reach here from the palette and Shift-I; this is complete only when the
                    // outline is carried onto the target face's parameters and tested on planes
                    // and curved faces.
                    throw KernelError(phase: .topology, code: .unsupportedCapability, featureID: featureID, tolerance: tolerance,
                        message: "Imprint cannot yet imprint a tool face that lies on a target face.")
                default:
                    let reference = BooleanFaceSplitComponentReference(facePair: split.facePair, componentID: component.id)
                    let onTarget = try BooleanFaceArrangementBoundary.edges(
                        reference: reference, geometry: component.geometry, faceID: faceID,
                        surfaceSide: .first, parentSubshapeIDs: parents, tolerance: tolerance
                    )
                    let onTool = try BooleanFaceArrangementBoundary.edges(
                        reference: reference, geometry: component.geometry, faceID: split.facePair.toolFaceID,
                        surfaceSide: .second, parentSubshapeIDs: parents, tolerance: tolerance
                    )
                    guard onTarget.count == onTool.count else {
                        throw KernelError(phase: .topology, code: .topologyFailure, featureID: featureID, tolerance: tolerance,
                            message: "A crossing is segmented differently on its two faces.")
                    }
                    for (target, tool) in zip(onTarget, onTool) {
                        pairs.append((BRepFaceImprinter.Curve(faceID: faceID, edge: target), tool))
                    }
                }
            }
        }
        return pairs
    }

    private func failure(_ code: KernelErrorCode, _ featureID: FeatureID, _ context: EvaluationContext, _ message: String) -> KernelError {
        KernelError(phase: .evaluation, code: code, featureID: featureID, tolerance: context.tolerance, message: message)
    }
}
