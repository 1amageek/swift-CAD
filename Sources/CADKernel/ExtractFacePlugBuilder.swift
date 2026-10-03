import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology

/// The solid that faces of a solid which do not close bound with the surfaces around them
/// (Plasticity's Alternative Duplicate): a pocket's plug, a boss's block.
///
/// The body is healed over the chosen faces (`FaceRemovalPlanner`, the faces around grown over
/// them until they meet) in a staged copy, and the opening — the edges where the chosen faces meet
/// the others — is imprinted on that copy (`BRepFaceImprinter`). The copy's faces off the source's
/// boundary are the caps closing the opening; the chosen faces and the caps are sewn as one solid,
/// the chosen faces turned inside out where they bound a void of the source (a pocket) and the caps
/// where they run through its material (a boss). The source stays as it is.
// FIXME(INCOMPLETE_IMPLEMENTATION): caps both inside and outside the source (faces that are partly
// pocket, partly boss) are refused, and so are faces the healing cannot grow the faces around over.
// Production path: ExtractFeatureEvaluator for `.solidFaces` that do not close, and
// ExtractFaceClosure.makesSolid, which answers a sheet for them. Complete only when such faces make
// the solid they bound, verified by a face set crossing the source's boundary making its two parts.
struct ExtractFacePlugBuilder {
    private let solver: BRepSurfaceMeetingSolver
    private let tolerance: ModelingTolerance

    init(tolerance: ModelingTolerance) {
        self.tolerance = tolerance
        self.solver = BRepSurfaceMeetingSolver(tolerance: tolerance)
    }

    func plug(faces chosen: Set<FaceID>, of bodyID: BodyID, featureID: FeatureID, context: EvaluationContext) throws -> EvaluationResult {
        let source = context.brep
        guard let body = source.bodies[bodyID] else { throw TopologyError.missingReference("The extracted body is missing.") }
        let bodyFaces = body.shellIDs.flatMap { source.shells[$0]?.faceIDs ?? [] }

        // The opening: the chosen faces' edges shared with a face that is not chosen.
        var facesOfEdge: [EdgeID: [FaceID]] = [:]
        for faceID in bodyFaces {
            for loopID in source.faces[faceID]?.loops ?? [] {
                for coedge in source.loops[loopID]?.coedges ?? [] { facesOfEdge[coedge.edgeID, default: []].append(faceID) }
            }
        }
        let opening = facesOfEdge.filter { _, faces in
            faces.contains(where: chosen.contains) && faces.contains { chosen.contains($0) == false }
        }.keys.sorted()
        guard opening.isEmpty == false else {
            throw failure(.invalidInput, featureID, "The faces have no edge in common with the rest of the body.")
        }

        // The body healed over the chosen faces, sewn on its own.
        var healed = source
        let healStage = featureEvaluationStageID(featureID: featureID, domain: .extractPlugHeal, ordinal: 0)
        try FaceRemovalPlanner().heal(removing: chosen, bodyID: bodyID, featureID: healStage, model: &healed, tolerance: tolerance)
        try ExactFacePcurveBuilder().populateMissingPcurves(in: &healed, tolerance: tolerance)
        let copyStage = featureEvaluationStageID(featureID: featureID, domain: .extractPlugCopy, ordinal: 0)
        let extraction = try DefaultBRepFacePatchExtractor().extract(
            bodyID: bodyID, featureID: copyStage, from: healed, sourceSubshapes: context.subshapes.entries, tolerance: tolerance
        )
        let filled = try DefaultBRepSewer().sew(BRepSewingRequest(
            featureID: copyStage, bodyTopology: extraction.request.bodyTopology, shells: extraction.request.shells
        ), tolerance: tolerance)
        let filledModel = filled.brep
        guard let filledBody = filledModel.bodies[filled.bodyID] else { throw TopologyError.missingReference("The healed body is missing.") }
        let filledFaces = filledBody.shellIDs.flatMap { filledModel.shells[$0]?.faceIDs ?? [] }

        // The opening imprinted on the healed faces it crosses; an edge the healed body already has
        // needs no imprint.
        let tester = DefaultFacePointContainmentTester()
        var curves: [BRepFaceImprinter.Curve] = []
        for (index, run) in try runs(along: opening, in: source).enumerated() {
            let (curve, low, high) = (run.curve, run.low, run.high)
            let start = try curve.point(at: low, tolerance: tolerance)
            let end = try curve.point(at: high, tolerance: tolerance)
            let middle = try curve.point(at: (low + high) / 2, tolerance: tolerance)
            if try runsAlongAnEdge(middle, of: filledModel, faces: filledFaces) { continue }
            var host: (faceID: FaceID, surface: Surface3D)?
            for faceID in filledFaces {
                guard let face = filledModel.faces[faceID], let surface = filledModel.geometry.surfaces[face.surfaceID],
                      (try solver.foot(of: middle, on: surface).point - middle).length <= tolerance.distance,
                      try tester.contains(middle, on: faceID, in: filledModel, tolerance: tolerance) else { continue }
                host = (faceID, surface)
                break
            }
            guard let host else {
                throw failure(.topologyFailure, featureID, "The healed body does not reach across the opening.")
            }
            let pcurve = try ExactFacePcurveBuilder().surfaceParameterCurve(
                for: curve, startParameter: low, endParameter: high, on: host.surface, tolerance: tolerance
            )
            curves.append(BRepFaceImprinter.Curve(faceID: host.faceID, edge: BRepSewingEdge(
                stableID: "plug:opening:\(index)", curve: curve, startParameter: low, endParameter: high,
                startPoint: start, endPoint: end, surfaceParameterCurve: pcurve, parentSubshapeIDs: []
            )))
        }
        var capped = filledModel
        var cappedBodyID = filled.bodyID
        if curves.isEmpty == false {
            var stageContext = context
            stageContext.brep = filledModel
            stageContext.validatedBRep = nil
            stageContext.subshapes.entries = filled.subshapes
            stageContext.lineage = filled.lineage
            let imprintStage = featureEvaluationStageID(featureID: featureID, domain: .extractPlugCopy, ordinal: 1)
            var stages = FeatureEvaluationStages(stageContext)
            let imprinted = try BRepFaceImprinter().imprint(curves, on: filled.bodyID, featureID: imprintStage, context: stageContext)
            stages.apply(imprinted)
            cappedBodyID = try stages.publishedBody(of: imprinted, featureID: featureID, what: "Imprinting the opening on the healed body")
            capped = stages.context.brep
        }
        guard let cappedBody = capped.bodies[cappedBodyID] else { throw TopologyError.missingReference("The imprinted body is missing.") }

        // The caps: the healed faces off the source's boundary, all on one side of it.
        let classifier = DefaultBRepSolidPointClassifier()
        let sampler = BRepFaceInteriorPointSampler()
        var caps: [FaceID] = []
        var sides = Set<SolidPointClassification>()
        for faceID in cappedBody.shellIDs.flatMap({ capped.shells[$0]?.faceIDs ?? [] }) {
            let point = try sampler.point(on: faceID, in: capped, tolerance: tolerance)
            let side = try classifier.classify(point, in: bodyID, model: source, tolerance: tolerance)
            guard side != .boundary else { continue }
            caps.append(faceID)
            sides.insert(side)
        }
        guard caps.isEmpty == false, sides.count == 1, let side = sides.first else {
            throw failure(.invalidInput, featureID, caps.isEmpty
                ? "The faces around the chosen ones close nothing with them."
                : "The faces bound both a void and material of the body.")
        }

        // A pocket's plug faces the void: its chosen faces turn inside out. A boss's block keeps
        // them and turns its caps.
        let pocket = side == .outside
        let orientation = BRepSewingPatchOrientationAdapter()
        func oriented(_ patch: BRepSewingFacePatch, flipped: Bool) throws -> BRepSewingFacePatch {
            guard flipped else { return patch }
            return try orientation.reorient(patch, to: patch.orientation == .forward ? .reversed : .forward, tolerance: tolerance)
        }
        var patches: [BRepSewingFacePatch] = []
        for (index, faceID) in bodyFaces.filter(chosen.contains).enumerated() {
            let patch = try SourceBRepFacePatchBuilder().build(
                faceID: faceID, stableID: "plug:face:\(index)", from: source, sourceSubshapes: context.subshapes.entries, tolerance: tolerance
            ).patch
            patches.append(try oriented(patch, flipped: pocket))
        }
        for (index, faceID) in caps.enumerated() {
            let patch = try SourceBRepFacePatchBuilder().build(
                faceID: faceID, stableID: "plug:cap:\(index)", from: capped, sourceSubshapes: [:], tolerance: tolerance
            ).patch
            patches.append(try oriented(patch, flipped: pocket == false))
        }
        let shells = try BRepSewingPatchShellPartitioner().shells(patches: try split(patches), stablePrefix: "plug:shell", tolerance: tolerance)
        let sewn = try DefaultBRepSewer().sew(BRepSewingRequest(featureID: featureID, bodyKind: .solid, shells: shells), tolerance: tolerance)
        var result = source
        try BRepModelCombiner().merge(sewn.brep, into: &result)
        // The chosen faces trace to their published faces; the caps, built from the staged body
        // alone, are generated by the feature.
        return EvaluationResult(brep: result, subshapes: sewn.subshapes, lineage: sewn.lineage)
    }

    /// The opening's edges with the edges along one curve that meet end to end joined into one
    /// run, a closed circle into its two halves: pieces of one curve imprinted apart overlap one
    /// another, which an imprint cannot cross.
    private func runs(along edges: [EdgeID], in model: BRepModel) throws -> [(curve: Curve3D, low: Double, high: Double)] {
        var pieces: [Curve3D: [(low: Double, high: Double)]] = [:]
        var order: [Curve3D] = []
        for edgeID in edges {
            guard let edge = model.edges[edgeID], let curve = model.geometry.curves[edge.curveID], let trim = edge.trim else {
                throw TopologyError.missingReference("An edge of the opening is missing.")
            }
            let period: Double?
            switch curve {
            case .circle: period = 2 * Double.pi
            default: period = nil
            }
            var low = min(trim.startParameter, trim.endParameter)
            var high = max(trim.startParameter, trim.endParameter)
            if let period {
                let shift = (low / period).rounded(.down) * period
                (low, high) = (low - shift, high - shift)
            }
            if pieces[curve] == nil { order.append(curve) }
            pieces[curve, default: []].append((low, high))
        }
        let gap = 1e-9
        var result: [(curve: Curve3D, low: Double, high: Double)] = []
        for curve in order {
            var merged: [(low: Double, high: Double)] = []
            for piece in (pieces[curve] ?? []).sorted(by: { $0.low < $1.low }) {
                if let last = merged.last, abs(last.high - piece.low) <= gap {
                    merged[merged.count - 1].high = piece.high
                } else {
                    merged.append(piece)
                }
            }
            switch curve {
            case .circle:
                let period = 2 * Double.pi
                if merged.count > 1, let first = merged.first, let last = merged.last, abs(last.high - (first.low + period)) <= gap {
                    merged.removeLast()
                    merged[0] = (last.low, first.high + period)
                }
                // A whole circle goes in two halves: an imprinted edge needs two distinct ends.
                if merged.count == 1, let whole = merged.first, abs(whole.high - whole.low - period) <= gap {
                    let half = whole.low + period / 2
                    merged = [(whole.low, half), (half, whole.high)]
                }
            default:
                break
            }
            result += merged.map { (curve, $0.low, $0.high) }
        }
        return result
    }

    /// The patches with every edge split where another patch's edge ends on it, so the chosen
    /// faces and the caps meet edge for edge however the opening was divided on each side.
    private func split(_ patches: [BRepSewingFacePatch]) throws -> [BRepSewingFacePatch] {
        let ends = patches.flatMap { $0.loops.flatMap(\.edges).flatMap { [$0.startPoint, $0.endPoint] } }
        let subdivider = BRepSewingEdgeSubdivider()
        return try patches.map { patch in
            BRepSewingFacePatch(
                stableID: patch.stableID, surface: patch.surface, orientation: patch.orientation,
                loops: try patch.loops.map { loop in
                    BRepSewingLoop(stableID: loop.stableID, role: loop.role, edges: try loop.edges.flatMap { edge -> [BRepSewingEdge] in
                        let inner = try subdivider.containedPoints(from: ends, on: edge, tolerance: tolerance).filter { point in
                            (point - edge.startPoint).length > tolerance.distance && (point - edge.endPoint).length > tolerance.distance
                        }
                        guard inner.isEmpty == false else { return [edge] }
                        return try subdivider.subdivide(edge, at: inner, tolerance: tolerance).enumerated().map { ordinal, piece in
                            BRepSewingEdge(
                                stableID: "\(edge.stableID):split:\(ordinal)", curve: piece.curve,
                                startParameter: piece.startParameter, endParameter: piece.endParameter,
                                startPoint: piece.startPoint, endPoint: piece.endPoint,
                                surfaceParameterCurve: piece.surfaceParameterCurve, parentSubshapeIDs: piece.parentSubshapeIDs
                            )
                        }
                    })
                },
                parentSubshapeIDs: patch.parentSubshapeIDs
            )
        }
    }

    private func runsAlongAnEdge(_ point: Point3D, of model: BRepModel, faces: [FaceID]) throws -> Bool {
        var seen = Set<EdgeID>()
        for faceID in faces {
            for loopID in model.faces[faceID]?.loops ?? [] {
                for coedge in model.loops[loopID]?.coedges ?? [] where seen.insert(coedge.edgeID).inserted {
                    guard let edge = model.edges[coedge.edgeID], let curve = model.geometry.curves[edge.curveID], let trim = edge.trim else {
                        throw TopologyError.missingReference("An edge of the healed body is missing.")
                    }
                    let closest = try solver.closest(to: point, on: curve)
                    let (low, high) = (min(trim.startParameter, trim.endParameter), max(trim.startParameter, trim.endParameter))
                    if (closest.point - point).length <= tolerance.distance * 8,
                       closest.parameter >= low - tolerance.distance, closest.parameter <= high + tolerance.distance {
                        return true
                    }
                }
            }
        }
        return false
    }

    private func failure(_ code: KernelErrorCode, _ featureID: FeatureID, _ message: String) -> KernelError {
        KernelError(phase: code == .topologyFailure ? .topology : .evaluation, code: code, featureID: featureID, tolerance: tolerance, message: message)
    }
}
