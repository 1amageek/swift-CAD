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
        let published = Set(context.subshapes.entries.keys)
        var completed: [BRepFaceImprinter.Curve] = []
        for (ordinal, tool) in imprint.tools.enumerated() {
            var toolBodyID = try context.bodyID(generatedBy: tool.body.featureID)
            var crossingContext = context
            if let placement = tool.placement {
                // The tool crosses the target where it is placed: moved in an unpublished stage.
                try placement.validate(tolerance: context.tolerance)
                var stages = FeatureEvaluationStages(context)
                let stageID = featureEvaluationStageID(featureID: feature.id, domain: .imprintToolPlacement, ordinal: UInt64(ordinal))
                let moved = try DefaultExactBodyPatternRebuilder(
                    sewer: DefaultBRepSewer(), unionApplicator: ExactBooleanOperationApplicator(), separationValidator: ExactBodyJoinValidator()
                ).relocate(featureID: stageID, sourceBodyID: toolBodyID, transform: placement, stablePrefix: "imprint:placedTool:\(ordinal)", context: context)
                stages.apply(moved)
                toolBodyID = try stages.publishedBody(of: moved, featureID: feature.id, what: "Moving the tool to imprint")
                crossingContext = stages.context
            }
            let curves = try Self.crossings(
                of: targetBodyID, by: toolBodyID, pipeline: pipeline, featureID: feature.id, context: crossingContext
            ).enumerated().map { index, curve in
                // A moved tool is never published: what the crossings trace to it is dropped.
                let edge = curve.edge
                return BRepFaceImprinter.Curve(faceID: curve.faceID, edge: BRepSewingEdge(
                    stableID: "imprint:tool:\(ordinal):\(index):\(edge.stableID)", curve: edge.curve,
                    startParameter: edge.startParameter, endParameter: edge.endParameter,
                    startPoint: edge.startPoint, endPoint: edge.endPoint, surfaceParameterCurve: edge.surfaceParameterCurve,
                    parentSubshapeIDs: edge.parentSubshapeIDs.filter(published.contains)
                ))
            }
            guard curves.isEmpty == false else {
                throw failure(.invalidInput, feature.id, context, "A tool does not cross the target.")
            }
            // Each tool's lines complete among themselves, so they run on across another tool's.
            completed += try BRepImprintCompletion().completed(
                curves, by: imprint.completion, model: context.brep, sourceSubshapes: context.subshapes.entries, tolerance: context.tolerance
            )
        }
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
                    let reference = BooleanFaceSplitComponentReference(facePair: split.facePair, componentID: component.id)
                    let outlines = try CoincidentBooleanFaceArrangementBoundaryBuilder().outlineEdges(
                        of: split.facePair.toolFaceID, onto: faceID, reference: reference,
                        model: context.brep, sourceSubshapes: context.subshapes.entries, tolerance: tolerance)
                    guard let toolFace = context.brep.faces[split.facePair.toolFaceID],
                          let toolSurface = context.brep.geometry.surfaces[toolFace.surfaceID] else {
                        throw TopologyError.missingReference("A coincident imprint tool support is missing.")
                    }
                    let targetEdges = try SourceBRepFacePatchBuilder().build(faceID: faceID,
                        stableID: "imprint:coincident:target", from: context.brep,
                        sourceSubshapes: context.subshapes.entries, tolerance: tolerance).patch.loops.flatMap(\.edges)
                    for edge in outlines {
                        var alreadyBoundsTarget = false
                        for targetEdge in targetEdges {
                            if case .coincident = try ExactTrimEdgeIntersector().intersections(
                                edge, targetEdge, tolerance: tolerance) {
                                alreadyBoundsTarget = true
                                break
                            }
                        }
                        guard !alreadyBoundsTarget else { continue }
                        let onTool = BRepSewingEdge(stableID: "\(edge.stableID):tool", curve: edge.curve,
                            startParameter: edge.startParameter, endParameter: edge.endParameter,
                            startPoint: edge.startPoint, endPoint: edge.endPoint,
                            surfaceParameterCurve: try ExactFacePcurveBuilder().surfaceParameterCurve(
                                for: edge.curve, startParameter: edge.startParameter,
                                endParameter: edge.endParameter, on: toolSurface, tolerance: tolerance),
                            parentSubshapeIDs: edge.parentSubshapeIDs,
                            startVertexParentSubshapeIDs: edge.startVertexParentSubshapeIDs,
                            endVertexParentSubshapeIDs: edge.endVertexParentSubshapeIDs)
                        pairs.append((BRepFaceImprinter.Curve(faceID: faceID, edge: edge), onTool))
                    }
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
