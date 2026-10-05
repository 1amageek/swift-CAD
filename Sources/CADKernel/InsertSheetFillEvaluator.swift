import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology

/// Surface fill: an opening filled by a built surface (`SurfaceFillFeatureEvaluator`), or with an
/// inserted sheet by that sheet trimmed to the opening (Plasticity's Insert Sheet, Trim to hole).
///
/// The opening's loop edges, lying on the inserted sheet, are imprinted on a staged copy of it
/// (`BRepFaceImprinter`, each edge's own curve with its parameter curve on the face it lies on),
/// and the part of the sheet they enclose — the faces reached from one another without crossing
/// the loop that touch none of the sheet's own open edges — is sewn as the fill's sheet. Its
/// boundary is the opening's edges themselves, so Join sews it into the opening exactly. The
/// inserted sheet itself is left as it is; its consumer takes its object away.
struct InsertSheetFillEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    private let fill: SurfaceFillFeatureEvaluator
    private let subshapeResolver = StableSubshapeResolver()

    init(fill: SurfaceFillFeatureEvaluator) {
        self.fill = fill
    }

    func evaluate(feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult {
        try evaluateValidated(feature: feature, context: context).result
    }

    func evaluateValidated(feature: FeatureNode, context: EvaluationContext) throws -> ValidatedFeatureEvaluation {
        guard case let .surfaceFill(surfaceFill) = feature.operation, let inserted = surfaceFill.insertedSheet else {
            return try fill.evaluateValidated(feature: feature, context: context)
        }
        return try FeatureEvaluationBoundary.evaluateValidated(featureID: feature.id, tolerance: context.tolerance) {
            try insert(inserted, into: surfaceFill, feature: feature, context: context)
        }
    }

    private func insert(_ inserted: FeatureID, into surfaceFill: SurfaceFillFeature, feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult {
        try FeatureEvaluationBoundary.validateRequest(featureID: feature.id, tolerance: context.tolerance) { try surfaceFill.validate() }
        guard feature.inputs == surfaceFill.inputs, feature.outputs.map(\.role) == [.sheet] else {
            throw FeatureEvaluationError.invalidGraph("Insert Sheet requires its opening's body, the inserted sheet and one sheet output.")
        }
        try FeatureEvaluationBoundary.validateExactInput(context, featureID: feature.id, tolerance: context.tolerance)
        let tolerance = context.tolerance
        let model = context.brep
        let baseBodyID = try context.bodyID(generatedBy: surfaceFill.targetFeatureID)
        let sheetBodyID = try context.bodyID(generatedBy: inserted)
        guard let base = model.bodies[baseBodyID], let sheet = model.bodies[sheetBodyID], sheet.kind == .sheet else {
            throw failure(.invalidInput, feature.id, tolerance, "Insert Sheet trims a sheet to an opening of another body.")
        }
        guard case let .edge(seedEdgeID) = try subshapeResolver.topologyReference(
            for: surfaceFill.boundarySeed, model: model, subshapes: context.subshapes, lineage: context.lineage, tolerance: tolerance
        ), let loop = OpenBoundaryLoopResolver().loop(startingAt: seedEdgeID, in: base, model: model) else {
            throw failure(.invalidInput, feature.id, tolerance, "Insert Sheet needs a closed loop of open edges around the opening.")
        }
        if surfaceFill.trimsToSheet {
            return try trimmedToSheet(base: base, sheet: sheet, hole: loop, feature: feature, context: context)
        }

        // Each loop edge on the inserted sheet's face it lies on.
        let sheetFaces = sheet.shellIDs.flatMap { model.shells[$0]?.faceIDs ?? [] }
        let solver = BRepSurfaceMeetingSolver(tolerance: tolerance)
        let tester = DefaultFacePointContainmentTester()
        var loopCurves: [(curve: Curve3D, low: Double, high: Double)] = []
        var curves: [BRepFaceImprinter.Curve] = []
        for (index, traversal) in loop.traversals.enumerated() {
            guard let edge = model.edges[traversal.edgeID], let curve = model.geometry.curves[edge.curveID], let trim = edge.trim,
                  let start = model.vertices[edge.startVertexID]?.point, let end = model.vertices[edge.endVertexID]?.point else {
                throw TopologyError.missingReference("An opening's edge is missing.")
            }
            loopCurves.append((curve, min(trim.startParameter, trim.endParameter), max(trim.startParameter, trim.endParameter)))
            let middle = try curve.point(at: (trim.startParameter + trim.endParameter) / 2, tolerance: tolerance)
            var host: (faceID: FaceID, surface: Surface3D)?
            for faceID in sheetFaces {
                guard let face = model.faces[faceID], let surface = model.geometry.surfaces[face.surfaceID],
                      (try solver.foot(of: middle, on: surface).point - middle).length <= tolerance.distance,
                      try tester.contains(middle, on: faceID, in: model, tolerance: tolerance) else { continue }
                host = (faceID, surface)
                break
            }
            guard let host else {
                throw failure(.invalidInput, feature.id, tolerance, "An edge of the opening does not lie on the inserted sheet.")
            }
            let pcurve = try ExactFacePcurveBuilder().surfaceParameterCurve(
                for: curve, startParameter: trim.startParameter, endParameter: trim.endParameter, on: host.surface, tolerance: tolerance
            )
            curves.append(BRepFaceImprinter.Curve(faceID: host.faceID, edge: BRepSewingEdge(
                stableID: "insert:loop:\(index)", curve: curve, startParameter: trim.startParameter, endParameter: trim.endParameter,
                startPoint: start, endPoint: end, surfaceParameterCurve: pcurve, parentSubshapeIDs: []
            )))
        }

        // The sheet split along the loop, in a stage of its own.
        var stages = FeatureEvaluationStages(context)
        let stageID = featureEvaluationStageID(featureID: feature.id, domain: .insertSheetImprint, ordinal: 0)
        let imprinted = try BRepFaceImprinter().imprint(curves, on: sheetBodyID, featureID: stageID, context: stages.context)
        stages.apply(imprinted)
        let splitID = try stages.publishedBody(of: imprinted, featureID: feature.id, what: "Splitting the inserted sheet along the opening")
        let split = stages.context.brep
        guard let splitBody = split.bodies[splitID] else { throw TopologyError.missingReference("The split sheet is missing.") }

        // Its faces, their edges, which of those run along the loop, and which are the sheet's own.
        var facesOfEdge: [EdgeID: [FaceID]] = [:]
        var orderedFaces: [(shellIndex: Int, faceIndex: Int, faceID: FaceID)] = []
        for (shellIndex, shellID) in splitBody.shellIDs.enumerated() {
            for (faceIndex, faceID) in (split.shells[shellID]?.faceIDs ?? []).enumerated() {
                orderedFaces.append((shellIndex, faceIndex, faceID))
                for loopID in split.faces[faceID]?.loops ?? [] {
                    for coedge in split.loops[loopID]?.coedges ?? [] { facesOfEdge[coedge.edgeID, default: []].append(faceID) }
                }
            }
        }
        func runsAlongLoop(_ edgeID: EdgeID) throws -> Bool {
            guard let edge = split.edges[edgeID], let curve = split.geometry.curves[edge.curveID], let trim = edge.trim else { return false }
            let middle = try curve.point(at: (trim.startParameter + trim.endParameter) / 2, tolerance: tolerance)
            for candidate in loopCurves {
                let closest = try solver.closest(to: middle, on: candidate.curve)
                if (closest.point - middle).length <= tolerance.distance * 8,
                   closest.parameter >= candidate.low - tolerance.distance, closest.parameter <= candidate.high + tolerance.distance {
                    return true
                }
            }
            return false
        }
        var loopEdges = Set<EdgeID>()
        for edgeID in facesOfEdge.keys where try runsAlongLoop(edgeID) { loopEdges.insert(edgeID) }
        let openEdges = Set(facesOfEdge.filter { $0.value.count == 1 }.keys).subtracting(loopEdges)
        // The parts of the sheet the loop separates; the enclosed one touches none of its open edges.
        var component: [FaceID: Int] = [:]
        var parts: [[FaceID]] = []
        for (_, _, start) in orderedFaces where component[start] == nil {
            var members: [FaceID] = []
            var queue = [start]
            component[start] = parts.count
            while let faceID = queue.popLast() {
                members.append(faceID)
                for loopID in split.faces[faceID]?.loops ?? [] {
                    for coedge in split.loops[loopID]?.coedges ?? [] where loopEdges.contains(coedge.edgeID) == false {
                        for next in facesOfEdge[coedge.edgeID] ?? [] where component[next] == nil {
                            component[next] = parts.count
                            queue.append(next)
                        }
                    }
                }
            }
            parts.append(members)
        }
        let enclosed = parts.filter { part in
            part.allSatisfy { faceID in
                (split.faces[faceID]?.loops ?? []).allSatisfy { loopID in
                    (split.loops[loopID]?.coedges ?? []).allSatisfy { openEdges.contains($0.edgeID) == false }
                }
            }
        }
        guard enclosed.count == 1, let inside = enclosed.first else {
            throw failure(.invalidInput, feature.id, tolerance, enclosed.isEmpty
                ? "The inserted sheet does not reach across the whole opening."
                : "The opening's loop encloses the inserted sheet more than once.")
        }

        // The enclosed faces, sewn as the fill's sheet.
        let extraction = try DefaultBRepFacePatchExtractor().extract(
            bodyID: splitID, featureID: feature.id, from: split, sourceSubshapes: stages.context.subshapes.entries, tolerance: tolerance
        )
        let chosen = Set(orderedFaces.filter { inside.contains($0.faceID) }.map { "shell:\($0.shellIndex):face:\($0.faceIndex)" })
        let patches = extraction.request.shells.flatMap(\.patches).filter { chosen.contains($0.stableID) }
        guard patches.count == inside.count else {
            throw failure(.topologyFailure, feature.id, tolerance, "Insert Sheet lost a face of the enclosed part.")
        }
        let shells = try BRepSewingPatchShellPartitioner().shells(patches: patches, stablePrefix: "insert:shell", tolerance: tolerance)
        let sewn = try DefaultBRepSewer().sew(BRepSewingRequest(featureID: feature.id, bodyKind: .sheet, shells: shells), tolerance: tolerance)
        var result = context.brep
        try BRepModelCombiner().merge(sewn.brep, into: &result)
        // The staged split is never published: the fill's topology is generated by the feature,
        // tracing to the inserted sheet's published faces and edges it came from.
        let published = Set(context.subshapes.entries.keys)
        let lineage = sewn.lineage.mapValues { entry in
            TopologyLineage(output: entry.output, parents: entry.parents.filter(published.contains), relation: .generated)
        }
        return EvaluationResult(brep: result, subshapes: sewn.subshapes, lineage: lineage)
    }

    /// Trim to sheet: the inserted sheet's open boundary, lying on the target around the opening, is
    /// imprinted on a staged copy of the target; the part of the target it encloses (the one holding
    /// the opening) goes, and the rest is sewn with the whole inserted sheet into one sheet.
    private func trimmedToSheet(base: Body, sheet: Body, hole: OpenBoundaryEdgeLoop, feature: FeatureNode,
                                context: EvaluationContext) throws -> EvaluationResult {
        let tolerance = context.tolerance
        let model = context.brep
        let rims = OpenBoundaryLoopResolver().loops(in: sheet, model: model)
        guard rims.count == 1, let rim = rims.first else {
            throw failure(.invalidInput, feature.id, tolerance, "Trim to sheet inserts a sheet with one open boundary.")
        }
        func span(_ edgeID: EdgeID) throws -> (curve: Curve3D, low: Double, high: Double, trim: CurveTrim, start: Point3D, end: Point3D) {
            guard let edge = model.edges[edgeID], let curve = model.geometry.curves[edge.curveID], let trim = edge.trim,
                  let start = model.vertices[edge.startVertexID]?.point, let end = model.vertices[edge.endVertexID]?.point else {
                throw TopologyError.missingReference("A boundary edge is missing.")
            }
            return (curve, min(trim.startParameter, trim.endParameter), max(trim.startParameter, trim.endParameter), trim, start, end)
        }
        let solver = BRepSurfaceMeetingSolver(tolerance: tolerance)
        let tester = DefaultFacePointContainmentTester()
        let baseFaces = base.shellIDs.flatMap { model.shells[$0]?.faceIDs ?? [] }
        // Each edge of the inserted sheet's boundary on the target's face it lies on.
        var rimCurves: [(curve: Curve3D, low: Double, high: Double)] = []
        var curves: [BRepFaceImprinter.Curve] = []
        for (index, traversal) in rim.traversals.enumerated() {
            let edge = try span(traversal.edgeID)
            rimCurves.append((edge.curve, edge.low, edge.high))
            let middle = try edge.curve.point(at: (edge.trim.startParameter + edge.trim.endParameter) / 2, tolerance: tolerance)
            var host: (faceID: FaceID, surface: Surface3D)?
            for faceID in baseFaces {
                guard let face = model.faces[faceID], let surface = model.geometry.surfaces[face.surfaceID],
                      (try solver.foot(of: middle, on: surface).point - middle).length <= tolerance.distance,
                      try tester.contains(middle, on: faceID, in: model, tolerance: tolerance) else { continue }
                host = (faceID, surface)
                break
            }
            guard let host else {
                throw failure(.invalidInput, feature.id, tolerance, "The inserted sheet's boundary does not lie on the sheet around the opening.")
            }
            let pcurve = try ExactFacePcurveBuilder().surfaceParameterCurve(
                for: edge.curve, startParameter: edge.trim.startParameter, endParameter: edge.trim.endParameter, on: host.surface, tolerance: tolerance
            )
            curves.append(BRepFaceImprinter.Curve(faceID: host.faceID, edge: BRepSewingEdge(
                stableID: "insert:rim:\(index)", curve: edge.curve, startParameter: edge.trim.startParameter, endParameter: edge.trim.endParameter,
                startPoint: edge.start, endPoint: edge.end, surfaceParameterCurve: pcurve, parentSubshapeIDs: []
            )))
        }
        let holeCurves = try hole.traversals.map { traversal -> (curve: Curve3D, low: Double, high: Double) in
            let edge = try span(traversal.edgeID)
            return (edge.curve, edge.low, edge.high)
        }

        // The target split along the inserted sheet's boundary, in a stage of its own.
        var stages = FeatureEvaluationStages(context)
        let stageID = featureEvaluationStageID(featureID: feature.id, domain: .insertSheetImprint, ordinal: 0)
        let imprinted = try BRepFaceImprinter().imprint(curves, on: base.id, featureID: stageID, context: stages.context)
        stages.apply(imprinted)
        let splitID = try stages.publishedBody(of: imprinted, featureID: feature.id, what: "Cutting the sheet along the inserted sheet's boundary")
        let split = stages.context.brep
        guard let splitBody = split.bodies[splitID] else { throw TopologyError.missingReference("The cut sheet is missing.") }
        var facesOfEdge: [EdgeID: [FaceID]] = [:]
        let splitFaces = splitBody.shellIDs.flatMap { split.shells[$0]?.faceIDs ?? [] }
        for faceID in splitFaces {
            for loopID in split.faces[faceID]?.loops ?? [] {
                for coedge in split.loops[loopID]?.coedges ?? [] { facesOfEdge[coedge.edgeID, default: []].append(faceID) }
            }
        }
        func runs(_ edgeID: EdgeID, along candidates: [(curve: Curve3D, low: Double, high: Double)]) throws -> Bool {
            guard let edge = split.edges[edgeID], let curve = split.geometry.curves[edge.curveID], let trim = edge.trim else { return false }
            let middle = try curve.point(at: (trim.startParameter + trim.endParameter) / 2, tolerance: tolerance)
            for candidate in candidates {
                let closest = try solver.closest(to: middle, on: candidate.curve)
                if (closest.point - middle).length <= tolerance.distance * 8,
                   closest.parameter >= candidate.low - tolerance.distance, closest.parameter <= candidate.high + tolerance.distance {
                    return true
                }
            }
            return false
        }
        var rimEdges = Set<EdgeID>(), holeEdges = Set<EdgeID>()
        for edgeID in facesOfEdge.keys {
            if try runs(edgeID, along: rimCurves) { rimEdges.insert(edgeID) }
            if facesOfEdge[edgeID]?.count == 1, try runs(edgeID, along: holeCurves) { holeEdges.insert(edgeID) }
        }
        let otherOpenEdges = Set(facesOfEdge.filter { $0.value.count == 1 }.keys).subtracting(holeEdges).subtracting(rimEdges)
        // The part of the target the boundary encloses: reached from the opening without crossing it.
        var dropped = Set<FaceID>()
        var queue = splitFaces.filter { faceID in
            (split.faces[faceID]?.loops ?? []).contains { (split.loops[$0]?.coedges ?? []).contains { holeEdges.contains($0.edgeID) } }
        }
        dropped.formUnion(queue)
        while let faceID = queue.popLast() {
            for loopID in split.faces[faceID]?.loops ?? [] {
                for coedge in split.loops[loopID]?.coedges ?? [] where rimEdges.contains(coedge.edgeID) == false {
                    for next in facesOfEdge[coedge.edgeID] ?? [] where dropped.insert(next).inserted { queue.append(next) }
                }
            }
        }
        guard holeEdges.isEmpty == false, dropped.count < splitFaces.count,
              dropped.allSatisfy({ faceID in
                  (split.faces[faceID]?.loops ?? []).allSatisfy { (split.loops[$0]?.coedges ?? []).allSatisfy { otherOpenEdges.contains($0.edgeID) == false } }
              }) else {
            throw failure(.invalidInput, feature.id, tolerance, "The inserted sheet's boundary does not enclose the opening on the sheet around it.")
        }

        // The rest of the target and the whole inserted sheet, sewn into one sheet.
        let builder = SourceBRepFacePatchBuilder()
        let kept = try splitFaces.filter { dropped.contains($0) == false }.enumerated().map { index, faceID in
            try builder.build(faceID: faceID, stableID: "trimmed:face:\(index)", from: split,
                              sourceSubshapes: stages.context.subshapes.entries, tolerance: tolerance).patch
        }
        let insertedFaces = sheet.shellIDs.flatMap { model.shells[$0]?.faceIDs ?? [] }
        let added = try insertedFaces.enumerated().map { index, faceID in
            try builder.build(faceID: faceID, stableID: "inserted:face:\(index)", from: model,
                              sourceSubshapes: context.subshapes.entries, tolerance: tolerance).patch
        }
        let shells = try BRepSewingPatchShellPartitioner().shells(patches: kept + added, stablePrefix: "insert:shell", tolerance: tolerance)
        guard shells.count == 1 else {
            throw failure(.topologyFailure, feature.id, tolerance, "Trim to sheet leaves the inserted sheet apart from the sheet around it.")
        }
        let sewn = try DefaultBRepSewer().sew(BRepSewingRequest(featureID: feature.id, bodyKind: .sheet, shells: shells), tolerance: tolerance)
        // The sewn sheet takes the target's place: the target is consumed, not joined afterwards.
        let result = try BRepBodyModelReplacer().replacing(bodyID: base.id, with: sewn.bodyID, from: sewn.brep, in: context.brep)
        let removed = try BodyTopologyScope(bodyID: base.id, model: context.brep).subshapeIDs(in: context.subshapes)
        // The inserted sheet's faces carry on from it; the trimmed target's come from the unpublished
        // stage, so they are generated.
        let published = Set(context.subshapes.entries.keys)
        let lineage = sewn.lineage.mapValues { entry in
            let parents = Array(Set(entry.parents.filter(published.contains))).sorted()
            return TopologyLineage(output: entry.output, parents: parents,
                                   relation: parents.isEmpty ? .generated : parents.count == 1 ? .preserved : .merged)
        }
        return EvaluationResult(brep: result, subshapes: sewn.subshapes, removedSubshapeIDs: removed, lineage: lineage)
    }

    private func failure(_ code: KernelErrorCode, _ featureID: FeatureID, _ tolerance: ModelingTolerance, _ message: String) -> KernelError {
        KernelError(phase: code == .topologyFailure ? .topology : .evaluation, code: code, featureID: featureID, tolerance: tolerance, message: message)
    }
}
