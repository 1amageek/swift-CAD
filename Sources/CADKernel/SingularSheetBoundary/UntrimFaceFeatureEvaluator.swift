import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology

/// A sheet of a face's untrimmed surface beside its body (`UntrimFaceFeature`). The sheet is one
/// face on the same surface, bounded by four parameter lines: in each direction the surface's own
/// domain where it is bounded, and the face's extent where it is unbounded or periodic, the whole
/// period when the face goes all the way around (its two ends then meet as a seam). Native cones
/// include the exact apex; a chart spanning both nappes publishes separate finite patches. Keeping edges
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
        var execution = try OriginalQueryExecution.kernelOriginal()
        return try evaluateValidated(feature: feature, context: context, using: &execution)
    }

    func evaluate(feature: FeatureNode, context: EvaluationContext,
        using execution: inout OriginalQueryExecution) throws -> EvaluationResult {
        try evaluateValidated(feature: feature, context: context, using: &execution).result
    }

    func evaluateValidated(feature: FeatureNode, context: EvaluationContext,
        using execution: inout OriginalQueryExecution) throws -> ValidatedFeatureEvaluation {
        try FeatureEvaluationBoundary.evaluateValidated(featureID: feature.id,
            tolerance: context.tolerance, using: &execution) { execution in
            try untrim(feature: feature, context: context, using: &execution)
        }
    }

    private func untrim(feature: FeatureNode, context: EvaluationContext, using execution: inout OriginalQueryExecution) throws -> EvaluationResult {
        guard case let .untrimFace(untrim) = feature.operation else {
            throw failure(.invalidInput, feature.id, context, "Untrim evaluator requires an untrimFace feature.")
        }
        try FeatureEvaluationBoundary.validateRequest(featureID: feature.id, tolerance: context.tolerance, using: &execution) {
            try untrim.validate()
        }
        try FeatureEvaluationBoundary.validateExactInput(context, featureID: feature.id, tolerance: context.tolerance, using: &execution)
        let tolerance = context.tolerance
        let subshapes = context.subshapes.entries
        let targetBodyID = try context.bodyID(generatedBy: untrim.target.featureID)
        let targetScope = try BodyTopologyScope(bodyID: targetBodyID, model: context.brep)
        guard case let .face(faceID) = try subshapeResolver.topologyReference(
            for: untrim.face, model: context.brep, subshapes: context.subshapes, lineage: context.lineage, tolerance: tolerance, maximumSubdivisionDepth: 32,
            remainingSourceDepth: 16, maximumAlgebraicDepth: 32, using: &execution), let face = context.brep.faces[faceID], let surface = context.brep.geometry.surfaces[face.surfaceID] else {
            throw failure(.missingReference, feature.id, context, "Untrim's face is not a face of its body.")
        }
        guard targetScope.references.contains(.face(faceID)) else {
            throw failure(.missingReference, feature.id, context, "Untrim's selected face belongs to a different target body.")
        }
        let extent = try FaceParameterExtentResolver().bounds(for: faceID, in: context.brep, tolerance: tolerance, using: &execution)
        let parameterLoops = try untrimmedParameterLoops(on: surface, extent: SurfaceParameterBox(u: extent.u, v: extent.v), tolerance: tolerance, using: &execution)
        let parents = try context.subshapeIDs(for: .face(faceID), using: &execution)
        try execution.retainKernelValues(count: parameterLoops.count, stride: MemoryLayout<BRepSewingShell>.stride)
        let shells = try parameterLoops.enumerated().map { patchOrdinal, sides -> BRepSewingShell in
            let prefix = parameterLoops.count == 1 ? "untrim" : "untrim:patch:\(patchOrdinal)"
            try execution.retainKernelValues(count: sides.count, stride: MemoryLayout<BRepSewingEdge>.stride)
            let edges = try sides.enumerated().map { index, side in
                try BRepFaceCurveClipper.edge(side, on: surface, stableID: "\(prefix):edge:\(index)", parentSubshapeIDs: parents, tolerance: tolerance, using: &execution)
            }
            // Coincident endpoints are admitted by exact sewing only when the original
            // iso law proves a complete closed span or a singular pole/apex boundary.
            // The loop runs counterclockwise in the parameters, which is the forward side; a
            // reversed face keeps its side by turning the patch over.
            let forward = BRepSewingFacePatch(
                stableID: "\(prefix):face", surface: surface, orientation: .forward,
                loops: [BRepSewingLoop(stableID: "\(prefix):loop", role: .outer, edges: edges)],
                parentSubshapeIDs: parents
            )
            let patch = try BRepSewingPatchOrientationAdapter().reorient(forward, to: face.orientation, tolerance: tolerance, using: &execution)
            return BRepSewingShell(stableID: "\(prefix):shell", patches: [patch])
        }
        let sewn = try sewer.sew(
            BRepSewingRequest(featureID: feature.id, bodyKind: .sheet, shells: shells, bodyParentSubshapeIDs: parents),
            tolerance: tolerance
        , using: &execution)
        var model = context.brep
        try BRepModelCombiner().merge(sewn.brep, into: &model, using: &execution)
        guard untrim.keepsEdges else {
            return EvaluationResult(brep: model, subshapes: sewn.subshapes, lineage: sewn.lineage)
        }
        // The face's boundary, where it does not lie on the sheet's edge, becomes edges on the sheet.
        var sheetContext = context
        sheetContext.brep = model
        sheetContext.subshapes = SubshapeIndex(context.subshapes.entries.merging(sewn.subshapes) { $1 })
        guard let sheet = sewn.brep.bodies[sewn.bodyID] else {
            throw failure(.topologyFailure, feature.id, context, "Untrim built no sheet body.")
        }
        let sheetFaceIDs = try sheet.shellIDs.flatMap { shellID -> [FaceID] in
            guard let shell = sewn.brep.shells[shellID] else {
                throw TopologyError.missingReference("Untrim sheet shell is missing.")
            }
            return shell.faceIDs
        }
        guard sheetFaceIDs.count == parameterLoops.count else {
            throw failure(.topologyFailure, feature.id, context, "Untrim did not retain every finite native patch.")
        }
        let boundary = try SourceBRepFacePatchBuilder().build(
            faceID: faceID, stableID: "untrim:source", from: context.brep, sourceSubshapes: subshapes, tolerance: tolerance
        , using: &execution).patch.loops.flatMap(\.edges)
        var curves: [BRepFaceImprinter.Curve] = []
        for (patchOrdinal, sheetFaceID) in sheetFaceIDs.enumerated() {
            let prefix = parameterLoops.count == 1 ? "untrim" : "untrim:patch:\(patchOrdinal)"
            for (index, edge) in boundary.enumerated() {
                curves += try BRepFaceCurveClipper().clip(
                    edge.surfaceParameterCurve, to: sheetFaceID,
                    stableID: "\(prefix):kept:\(index)", parentSubshapeIDs: edge.parentSubshapeIDs,
                    model: model, sourceSubshapes: sheetContext.subshapes.entries, alongEdge: .yieldNothing, tolerance: tolerance
                , using: &execution).map { BRepFaceImprinter.Curve(faceID: sheetFaceID, edge: $0) }
            }
        }
        guard curves.isEmpty == false else {
            return EvaluationResult(brep: model, subshapes: sewn.subshapes, lineage: sewn.lineage)
        }
        let imprinted = try BRepFaceImprinter(sewer: sewer).imprint(curves, on: sewn.bodyID, featureID: feature.id, context: sheetContext, using: &execution)
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

    /// Construct boundaries in their original chart before retaining each foreign image.
    private func untrimmedParameterLoops(on surface: Surface3D, extent: SurfaceParameterBox,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> [[SurfaceParameterCurve]] {
        try execution.checkpoint(); try execution.admitSourceDepth(0); try execution.consumeWork(1)
        if case let .procedural(.originalAffineWord(image)) = surface {
            let originalLoops = try execution.withSourceDepthOffset(1) { execution in
                try untrimmedParameterLoops(on: image.source, extent: extent, tolerance: tolerance, using: &execution)
            }
            return try originalLoops.map { originalSides in
                try originalSides.map { side in
                    .originalAffineWord(try OriginalAffineWordSurfaceParameterCurve(
                        source: SurfaceLiftCurve3D(surface: image.source, parameterCurve: side),
                        target: image, tolerance: tolerance,
                        remainingSourceDepth: min(16, execution.effectiveLimits.remainingSourceDepth),
                        maximumSubdivisionDepth: min(32, execution.effectiveLimits.maximumSubdivisionDepth),
                        usage: &execution))
                }
            }
        }
        if case let .procedural(.originalImage(image)) = surface {
            let originalExtent = try image.sourceParameterBounds(over: extent, tolerance: tolerance, using: &execution)
            let originalLoops = try execution.withSourceDepthOffset(1) { execution in
                try untrimmedParameterLoops(on: image.source, extent: originalExtent, tolerance: tolerance, using: &execution)
            }
            let reversesChart = ((image.uGain < 0) != (image.vGain < 0)) != image.swapAxes
            return try originalLoops.map { originalSides in
                let sides = try originalSides.map { side -> SurfaceParameterCurve in
                    .originalImage(try OriginalImageSurfaceParameterCurve(
                        source: SurfaceLiftCurve3D(surface: image.source, parameterCurve: side),
                        targetImage: image, tolerance: tolerance, using: &execution))
                }
                return reversesChart ? try sides.reversed().map { try $0.reversed(tolerance: tolerance, using: &execution) } : sides
            }
        }
        let u = untrimmed(extent.u.lower...extent.u.upper, within: surface.uDomain, tolerance: tolerance)
        let v = untrimmed(extent.v.lower...extent.v.upper, within: surface.vDomain, tolerance: tolerance)
        let vRanges: [ClosedRange<Double>]
        if case .analytic(.cone) = surface {
            let lower = min(v.lowerBound, 0.0), upper = max(v.upperBound, 0.0)
            vRanges = lower < 0 && upper > 0 ? [lower...0, 0...upper] : [lower...upper]
        } else {
            vRanges = [v]
        }
        return vRanges.map { v in
            [
                .constantV(v: v.lowerBound, uStart: u.lowerBound, uEnd: u.upperBound),
                .constantU(u: u.upperBound, vStart: v.lowerBound, vEnd: v.upperBound),
                .constantV(v: v.upperBound, uStart: u.upperBound, uEnd: u.lowerBound),
                .constantU(u: u.lowerBound, vStart: v.upperBound, vEnd: v.lowerBound),
            ]
        }
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
