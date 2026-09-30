import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology

/// A sheet of a face's untrimmed surface beside its body (`UntrimFaceFeature`). The sheet is one
/// face on the same surface, bounded by four parameter lines: in each direction the surface's own
/// domain where it is bounded, and the face's extent where it is unbounded or periodic, the whole
/// period when the face goes all the way around (its two ends then meet as a seam). Keeping edges
/// imprints the face's own boundary on the sheet (`BRepFaceImprinter`), except where it already
/// lies on the sheet's edge. The body is left as it is.
struct UntrimFaceFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    private let subshapeResolver: any StableSubshapeResolving
    private let sewer: any BRepSewing

    init(subshapeResolver: any StableSubshapeResolving = StableSubshapeResolver(), sewer: any BRepSewing = DefaultBRepSewer()) {
        self.subshapeResolver = subshapeResolver
        self.sewer = sewer
    }

    func evaluate(feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult {
        try evaluateValidated(feature: feature, context: context).result
    }

    func evaluateValidated(feature: FeatureNode, context: EvaluationContext) throws -> ValidatedFeatureEvaluation {
        try FeatureEvaluationBoundary.evaluateValidated(featureID: feature.id, tolerance: context.tolerance) {
            try untrim(feature: feature, context: context)
        }
    }

    private func untrim(feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult {
        guard case let .untrimFace(untrim) = feature.operation else {
            throw failure(.invalidInput, feature.id, context, "Untrim evaluator requires an untrimFace feature.")
        }
        try FeatureEvaluationBoundary.validateRequest(featureID: feature.id, tolerance: context.tolerance) {
            try untrim.validate()
        }
        try FeatureEvaluationBoundary.validateExactInput(context, featureID: feature.id, tolerance: context.tolerance)
        let tolerance = context.tolerance
        let subshapes = context.subshapes.entries
        _ = try context.bodyID(generatedBy: untrim.target.featureID)
        guard case let .face(faceID) = try subshapeResolver.topologyReference(
            for: untrim.face, model: context.brep, subshapes: context.subshapes, lineage: context.lineage, tolerance: tolerance
        ), let face = context.brep.faces[faceID], let surface = context.brep.geometry.surfaces[face.surfaceID] else {
            throw failure(.missingReference, feature.id, context, "Untrim's face is not a face of its body.")
        }
        let extent = try BRepFaceCurveClipper.parameterBounds(of: faceID, model: context.brep, sourceSubshapes: subshapes, tolerance: tolerance)
        let u = untrimmed(extent.u, within: surface.uDomain, tolerance: tolerance)
        let v = untrimmed(extent.v, within: surface.vDomain, tolerance: tolerance)
        let parents = context.subshapeIDs(for: .face(faceID))
        let sides: [SurfaceParameterCurve] = [
            .constantV(v: v.lowerBound, uStart: u.lowerBound, uEnd: u.upperBound),
            .constantU(u: u.upperBound, vStart: v.lowerBound, vEnd: v.upperBound),
            .constantV(v: v.upperBound, uStart: u.upperBound, uEnd: u.lowerBound),
            .constantU(u: u.lowerBound, vStart: v.upperBound, vEnd: v.lowerBound),
        ]
        let edges = try sides.enumerated().map { index, side in
            try BRepFaceCurveClipper.edge(side, on: surface, stableID: "untrim:edge:\(index)", parentSubshapeIDs: parents, tolerance: tolerance)
        }
        guard edges.allSatisfy({ ($0.startPoint - $0.endPoint).length > tolerance.distance }) else {
            // FIXME(INCOMPLETE_IMPLEMENTATION): A surface whose untrimmed side collapses to a
            // point (a sphere's pole, a cone's apex) needs a singular vertex on that side. Untrim
            // reaches here from Alt-T and the palette; it is complete only when such sheets are
            // built with their degenerate side and tested on a sphere and a cone.
            throw KernelError(phase: .topology, code: .unsupportedCapability, featureID: feature.id, tolerance: tolerance,
                message: "Untrim cannot yet build a sheet whose side collapses to a point.")
        }
        // The loop runs counterclockwise in the parameters, which is the forward side; a
        // reversed face keeps its side by turning the patch over.
        let forward = BRepSewingFacePatch(
            stableID: "untrim:face", surface: surface, orientation: .forward,
            loops: [BRepSewingLoop(stableID: "untrim:loop", role: .outer, edges: edges)],
            parentSubshapeIDs: parents
        )
        let patch = try BRepSewingPatchOrientationAdapter().reorient(forward, to: face.orientation, tolerance: tolerance)
        let sewn = try sewer.sew(
            BRepSewingRequest(featureID: feature.id, bodyKind: .sheet, shells: [BRepSewingShell(stableID: "untrim:shell", patches: [patch])]),
            tolerance: tolerance
        )
        var model = context.brep
        try BRepModelCombiner().merge(sewn.brep, into: &model)
        guard untrim.keepsEdges else {
            return EvaluationResult(brep: model, subshapes: sewn.subshapes, lineage: sewn.lineage)
        }
        // The face's boundary, where it does not lie on the sheet's edge, becomes edges on the sheet.
        var sheetContext = context
        sheetContext.brep = model
        sheetContext.subshapes = SubshapeIndex(context.subshapes.entries.merging(sewn.subshapes) { $1 })
        guard let sheet = sewn.brep.bodies[sewn.bodyID], let sheetShell = sheet.shellIDs.first,
              let sheetFaceID = sewn.brep.shells[sheetShell]?.faceIDs.first else {
            throw failure(.topologyFailure, feature.id, context, "Untrim built no sheet face.")
        }
        let boundary = try SourceBRepFacePatchBuilder().build(
            faceID: faceID, stableID: "untrim:source", from: context.brep, sourceSubshapes: subshapes, tolerance: tolerance
        ).patch.loops.flatMap(\.edges)
        var curves: [BRepFaceImprinter.Curve] = []
        for (index, edge) in boundary.enumerated() {
            curves += try BRepFaceCurveClipper().clip(
                edge.surfaceParameterCurve, to: sheetFaceID, stableID: "untrim:kept:\(index)", parentSubshapeIDs: edge.parentSubshapeIDs,
                model: model, sourceSubshapes: sheetContext.subshapes.entries, alongEdge: .yieldNothing, tolerance: tolerance
            ).map { BRepFaceImprinter.Curve(faceID: sheetFaceID, edge: $0) }
        }
        guard curves.isEmpty == false else {
            return EvaluationResult(brep: model, subshapes: sewn.subshapes, lineage: sewn.lineage)
        }
        let imprinted = try BRepFaceImprinter(sewer: sewer).imprint(curves, on: sewn.bodyID, featureID: feature.id, context: sheetContext)
        // The bare sheet is never published, so what the imprint traces to it traces on to the
        // face it was untrimmed from.
        let lineage = imprinted.lineage.mapValues { entry in
            let parents = Array(Set(entry.parents.flatMap { parent in
                sewn.subshapes[parent] == nil ? [parent] : (sewn.lineage[parent]?.parents ?? [])
            })).sorted()
            let relation: TopologyLineageRelation = switch (entry.relation, parents.count) {
            case (_, 0): .generated
            case (.split, 1): .split
            case (_, 1): .preserved
            default: .merged
            }
            return TopologyLineage(output: entry.output, parents: parents, relation: relation)
        }
        return EvaluationResult(brep: imprinted.brep, subshapes: imprinted.subshapes, lineage: lineage)
    }

    /// The untrimmed range in one parameter direction.
    private func untrimmed(_ extent: ClosedRange<Double>, within domain: ParameterDomain, tolerance: ModelingTolerance) -> ClosedRange<Double> {
        switch domain {
        case .unbounded:
            return extent
        case let .closed(lower, upper):
            return lower...upper
        case let .periodic(period):
            return extent.upperBound - extent.lowerBound >= period - tolerance.angle
                ? extent.lowerBound...(extent.lowerBound + period)
                : extent
        }
    }

    private func failure(_ code: KernelErrorCode, _ featureID: FeatureID, _ context: EvaluationContext, _ message: String) -> KernelError {
        KernelError(phase: .evaluation, code: code, featureID: featureID, tolerance: context.tolerance, message: message)
    }
}
