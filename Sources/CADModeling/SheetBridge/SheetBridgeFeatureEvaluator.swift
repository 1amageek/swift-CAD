import Foundation
import CADCore
import CADGeometry
import CADIR
import CADTopology

/// Bridge Surface between two planar sheets: the planes' meeting line L, each sheet's direction
/// away from L in its plane, the contact lines `width` along them, and the bridge swept along L
/// over the stretch both sheets cover: a quintic whose first and last three control points lie on
/// the sheets' planes (tangent and curvature continuous with them) or a straight chamfer. Trimmed
/// walls are cut at their contact lines, keeping the side away from L, and joined with the bridge
/// into one sheet.
public struct SheetBridgeFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    private let sewer: any BRepSewing
    private let resolver: ParameterResolving
    private let cutter: (any BodyHalfSpaceCutting)?
    private let joiner: (any SheetBodyJoining)?

    package init(sewer: any BRepSewing, resolver: ParameterResolving = ParameterResolver(),
                 cutter: (any BodyHalfSpaceCutting)? = nil, joiner: (any SheetBodyJoining)? = nil) {
        self.sewer = sewer
        self.resolver = resolver
        self.cutter = cutter
        self.joiner = joiner
    }

    public func evaluate(feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult {
        try evaluateValidated(feature: feature, context: context).result
    }

    package func evaluateValidated(feature: FeatureNode, context: EvaluationContext) throws -> ValidatedFeatureEvaluation {
        try FeatureEvaluationBoundary.evaluateValidated(featureID: feature.id, tolerance: context.tolerance) {
            try evaluateUnvalidated(feature: feature, context: context)
        }
    }

    private func evaluateUnvalidated(feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult {
        let tolerance = context.tolerance
        guard case let .sheetBridge(bridge) = feature.operation else {
            throw KernelError(phase: .validation, code: .invalidInput, featureID: feature.id, tolerance: tolerance,
                              message: "SheetBridgeFeatureEvaluator requires a Bridge Surface feature.")
        }
        try bridge.validate()
        func failure(_ code: KernelErrorCode, _ message: String) -> KernelError {
            KernelError(phase: .evaluation, code: code, featureID: feature.id, tolerance: tolerance, message: message)
        }
        // Sheets that are not two planes meeting, or named boundary edges: the bridge between edges.
        let planesMeet = try SheetBridgeLayout.meets(first: bridge.first, second: bridge.second, context: context)
        if bridge.edges != nil || planesMeet == false {
            return try edgeBridge(bridge, feature: feature, context: context)
        }
        let width = try resolver.evaluate(bridge.width, parameters: context.parameters, variables: [:])
        guard width.kind == .length, width.value.isFinite, width.value > tolerance.distance else {
            throw failure(.invalidInput, "A Bridge Surface's width is a positive length.")
        }
        let layout = try SheetBridgeLayout(first: bridge.first, second: bridge.second, reversesSense: bridge.reversesSense,
                                           featureID: feature.id, context: context)
        let (a, b, d, lineOrigin) = (layout.first, layout.second, layout.direction, layout.lineOrigin)
        guard a.reach >= width.value - tolerance.distance, b.reach >= width.value - tolerance.distance else {
            throw failure(.invalidInput, "A bridged sheet does not reach the bridge's width from where the sheets meet.")
        }
        let (m1, m2) = (a.away, b.away)
        let (t0, t1) = (max(a.stretch.low, b.stretch.low), min(a.stretch.high, b.stretch.high))
        guard t1 - t0 > tolerance.distance else {
            throw failure(.invalidInput, "The bridged sheets share no stretch along where they meet.")
        }
        // The cross-section at the stretch's start, swept along the line.
        let corner = lineOrigin + d * t0
        let p1 = corner + m1 * width.value, p2 = corner + m2 * width.value
        let section: [Point3D]
        switch bridge.shape {
        case .curvature:
            let handle = bridge.tension * width.value / 3
            let h1: Point3D = p1 + m1 * -handle
            let k1: Point3D = p1 + m1 * (-2 * handle)
            let k2: Point3D = p2 + m2 * (-2 * handle)
            let h2: Point3D = p2 + m2 * -handle
            section = [p1, h1, k1, k2, h2, p2]
        case .chamfer:
            section = [p1, p2]
        }
        let degree = section.count - 1
        let knots = Array(repeating: 0.0, count: degree + 1) + Array(repeating: 1.0, count: degree + 1)
        let lift = d * (t1 - t0)
        let surface = BSplineSurface3D(uDegree: degree, vDegree: 1, uKnots: knots, vKnots: [0, 0, 1, 1],
                                       controlPoints: [section, section.map { $0 + lift }])
        try surface.validate(tolerance: tolerance)
        let patch = try ExactLinearSectionSweepFacePatchBuilder(tolerance: tolerance)
            .tensorSidePatch(surface: surface, orientation: .forward, stableID: "bridgeSurface:face")
        let trimmed: [(SheetBridgeLayout.Sheet, Point3D)]
        switch bridge.trimWalls {
        case .none: trimmed = []
        case .both: trimmed = [(a, p1), (b, p2)]
        case .first: trimmed = [(a, p1)]
        case .second: trimmed = [(b, p2)]
        }
        guard trimmed.isEmpty == false else {
            let sewn = try sewer.sew(BRepSewingRequest(featureID: feature.id, bodyKind: .sheet,
                shells: [BRepSewingShell(stableID: "bridgeSurface:shell", patches: [patch])]), tolerance: tolerance)
            return EvaluationResult(brep: try BRepModelCombiner().combined([context.brep, sewn.brep]),
                                    subshapes: sewn.subshapes, lineage: sewn.lineage)
        }
        guard let cutter, let joiner else {
            throw failure(.unsupportedCapability, "This evaluator cannot trim a Bridge Surface's walls.")
        }
        // Stages: each trimmed wall cut at its contact line keeping the side away from L, then the
        // bridge beside them; all joined into the feature's one sheet.
        var stages = FeatureEvaluationStages(context)
        var joined: [BodyID] = []
        for (ordinal, (sheet, contact)) in trimmed.enumerated() {
            let stageID = featureEvaluationStageID(featureID: feature.id, domain: .sheetBridgeTrim, ordinal: UInt64(ordinal))
            guard let cut = try cutter.cut(bodyID: sheet.bodyID, planeOrigin: contact, planeNormal: sheet.away * -1,
                                           featureID: stageID, context: stages.context) else {
                throw failure(.invalidInput, "A trimmed wall lies wholly beyond the bridge's contact.")
            }
            stages.apply(cut)
            joined.append(try stages.publishedBody(of: cut, featureID: feature.id, what: "Trimming a Bridge Surface's wall"))
        }
        let bridgeStage = featureEvaluationStageID(featureID: feature.id, domain: .sheetBridgeTrim, ordinal: 2)
        let bridged = try sewer.sew(BRepSewingRequest(featureID: bridgeStage, bodyKind: .sheet,
            shells: [BRepSewingShell(stableID: "bridgeSurface:shell", patches: [patch])]), tolerance: tolerance)
        stages.apply(EvaluationResult(brep: try BRepModelCombiner().combined([stages.context.brep, bridged.brep]),
                                      subshapes: bridged.subshapes, lineage: bridged.lineage))
        joined.append(bridged.bodyID)
        let sewn = try joiner.joinSheets(bodyIDs: joined, closed: false, featureID: feature.id, context: stages.context)
        let replaced = try joined.reduce(into: Set<SubshapeID>()) { result, bodyID in
            result.formUnion(try BodyTopologyScope(bodyID: bodyID, model: stages.context.brep).subshapeIDs(in: stages.context.subshapes))
        }
        let model = try BRepBodyModelReplacer().replacing(bodyIDs: Set(joined), with: sewn.brep, in: stages.context.brep)
        return try stages.publish(EvaluationResult(brep: model, subshapes: sewn.subshapes,
                                                   removedSubshapeIDs: replaced, lineage: sewn.lineage), featureID: feature.id)
    }

    /// The bridge between a boundary edge of each sheet — the named ones, or the pair nearest each
    /// other — lofted between them, continuous with both sheets there: curvature continuous (G2,
    /// with the tension) or a straight chamfer (G0). The sheets stay as they are.
    private func edgeBridge(_ bridge: SheetBridgeFeature, feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult {
        let tolerance = context.tolerance
        func failure(_ code: KernelErrorCode, _ message: String) -> KernelError {
            KernelError(phase: .evaluation, code: code, featureID: feature.id, tolerance: tolerance, message: message)
        }
        guard bridge.trimWalls == .none else {
            // FIXME(INCOMPLETE_IMPLEMENTATION): a bridge between boundary edges joined with its
            // sheets into one sheet is not built, so Trim walls is refused there. Production path:
            // SheetBridgeFeatureEvaluator.edgeBridge. Complete only when the bridge and both sheets
            // join, verified by two cylinder sheets bridged and joined.
            throw failure(.unsupportedCapability, "A Bridge Surface between boundary edges leaves its sheets whole; Trim walls takes two planes meeting.")
        }
        let resolver = StableSubshapeResolver()
        func boundaryEdges(_ featureID: FeatureID) throws -> [EdgeID] {
            let scope = try BodyTopologyScope(bodyID: try context.bodyID(generatedBy: featureID), model: context.brep)
            var uses: [EdgeID: Int] = [:]
            for case let .face(faceID) in scope.references {
                for loopID in context.brep.faces[faceID]?.loops ?? [] {
                    for coedge in context.brep.loops[loopID]?.coedges ?? [] { uses[coedge.edgeID, default: 0] += 1 }
                }
            }
            return uses.filter { $0.value == 1 }.map(\.key).sorted()
        }
        func edgeID(_ reference: StableSubshapeReference, of featureID: FeatureID) throws -> EdgeID {
            guard case let .edge(id) = try resolver.topologyReference(for: reference, model: context.brep, subshapes: context.subshapes,
                                                                     lineage: context.lineage, tolerance: tolerance),
                  try boundaryEdges(featureID).contains(id) else {
                throw failure(.invalidInput, "A Bridge Surface's named edge is a boundary edge of its sheet.")
            }
            return id
        }
        func ends(_ id: EdgeID) throws -> (Point3D, Point3D) {
            guard let edge = context.brep.edges[id], let a = context.brep.vertices[edge.startVertexID]?.point,
                  let b = context.brep.vertices[edge.endVertexID]?.point else { throw TopologyError.missingReference("A bridged edge is missing.") }
            return (a, b)
        }
        let (firstEdge, secondEdge): (EdgeID, EdgeID)
        if let named = bridge.edges {
            (firstEdge, secondEdge) = (try edgeID(named.first, of: bridge.first), try edgeID(named.second, of: bridge.second))
        } else {
            // The boundary edges nearest each other, by their middles.
            var best: (EdgeID, EdgeID, Double)?
            for a in try boundaryEdges(bridge.first) {
                let (a0, a1) = try ends(a)
                for b in try boundaryEdges(bridge.second) {
                    let (b0, b1) = try ends(b)
                    let gap = ((a0 - .origin) + (a1 - .origin) - (b0 - .origin) - (b1 - .origin)).length / 2
                    if let current = best, gap >= current.2 - tolerance.distance { continue }
                    best = (a, b, gap)
                }
            }
            guard let best else { throw failure(.invalidInput, "A bridged sheet has no boundary edge.") }
            (firstEdge, secondEdge) = (best.0, best.1)
        }
        // Each edge as a curve section, the second run the way the first does.
        func curve(_ id: EdgeID, as featureID: FeatureID) throws -> EvaluatedCurve {
            guard let edge = context.brep.edges[id], let exact = context.brep.geometry.curves[edge.curveID], let trim = edge.trim else {
                throw TopologyError.missingReference("A bridged edge has no curve.")
            }
            let (lower, upper) = (min(trim.startParameter, trim.endParameter), max(trim.startParameter, trim.endParameter))
            let parameters = (0...32).map { lower + (upper - lower) * Double($0) / 32 }
            return EvaluatedCurve(sourceFeatureID: featureID, source: .generatedFeature, kind: .spline,
                                  points: try parameters.map { try exact.point(at: $0, tolerance: tolerance) },
                                  exactCurve: exact, exactParameterDomain: .closed(lower, upper), exactPointParameters: parameters)
        }
        let (curveA, curveB) = (featureEvaluationStageID(featureID: feature.id, domain: .sheetBridgeTrim, ordinal: 10),
                                featureEvaluationStageID(featureID: feature.id, domain: .sheetBridgeTrim, ordinal: 11))
        let (sectionA, sectionB) = (try curve(firstEdge, as: curveA), try curve(secondEdge, as: curveB))
        guard let a0 = sectionA.points.first, let a1 = sectionA.points.last, let b0 = sectionB.points.first, let b1 = sectionB.points.last else {
            throw TopologyError.missingReference("A bridged edge has no points.")
        }
        let reversed = (a0 - b0).length + (a1 - b1).length > (a0 - b1).length + (a1 - b0).length
        var augmented = context
        augmented.curves[curveA] = [sectionA]
        augmented.curves[curveB] = [sectionB]
        func continuity(_ source: FeatureID, _ edge: EdgeID) throws -> SurfaceEdgeContinuity? {
            guard bridge.shape == .curvature else { return nil }
            guard let subshapeID = context.subshapeIDs(for: .edge(edge)).first else {
                throw failure(.missingReference, "A bridged edge has no identity.")
            }
            let reference = StableSubshapeReference(subshapeID: subshapeID, geometrySignature: try SubshapeGeometrySignatureBuilder(
                model: context.brep, tolerance: tolerance).signature(for: .edge(edge)))
            return SurfaceEdgeContinuity(source: source, bodyRole: .sheet, edge: reference, order: .curvature, tension: bridge.tension,
                                         angularAllowance: bridge.angularAllowance, curvatureAllowance: bridge.curvatureAllowance)
        }
        let loft = LoftFeature(sections: [
            LoftSectionReference(section: .curve(CurveSectionReference(featureID: curveA)), continuity: try continuity(bridge.first, firstEdge)),
            LoftSectionReference(section: .curve(CurveSectionReference(featureID: curveB, isReversed: reversed)),
                                 continuity: try continuity(bridge.second, secondEdge)),
        ], options: LoftOptions(resultKind: .sheet))
        return try LoftFeatureEvaluator(sewer: sewer).evaluate(feature: FeatureNode(id: feature.id, operation: .loft(loft)), context: augmented)
    }
}
