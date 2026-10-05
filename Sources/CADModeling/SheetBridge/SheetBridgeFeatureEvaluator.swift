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
        let width = try resolver.evaluate(bridge.width, parameters: context.parameters, variables: [:])
        guard width.kind == .length, width.value.isFinite, width.value > tolerance.distance else {
            throw failure(.invalidInput, "A Bridge Surface's width is a positive length.")
        }
        // Curved sheets whose continuations meet: walls carried to their contacts the width from
        // where they meet, bridged between those contacts.
        if bridge.edges == nil, planesMeet == false, bridge.propagates == false,
           let walls = try CurvedSheetBridgeWalls(tolerance: tolerance).walls(
               first: try context.bodyID(generatedBy: bridge.first), second: try context.bodyID(generatedBy: bridge.second),
               width: width.value, featureID: feature.id, context: context) {
            return try curvedBridge(bridge, walls: walls, feature: feature, context: context)
        }
        if bridge.edges != nil || planesMeet == false {
            return try edgeBridge(bridge, feature: feature, context: context)
        }
        let layout = try SheetBridgeLayout(first: bridge.first, second: bridge.second, reversesFirstSense: bridge.reversesFirstSense,
                                           reversesSecondSense: bridge.reversesSecondSense,
                                           featureID: feature.id, context: context)
        let (a, b, d, lineOrigin) = (layout.first, layout.second, layout.direction, layout.lineOrigin)
        guard a.reach >= width.value - tolerance.distance, b.reach >= width.value - tolerance.distance else {
            throw failure(.invalidInput, "A bridged sheet does not reach the bridge's width from where the sheets meet.")
        }
        let (m1, m2) = (a.away, b.away)
        // How far the bridge runs along L: the shared stretch, the shorter or longer sheet's own,
        // or both together run on by the width at each end (untrimmed).
        let (t0, t1): (Double, Double)
        switch bridge.extent {
        case .both:
            (t0, t1) = (max(a.stretch.low, b.stretch.low), min(a.stretch.high, b.stretch.high))
        case .short, .long:
            let (aLength, bLength) = (a.stretch.high - a.stretch.low, b.stretch.high - b.stretch.low)
            let shorter = aLength <= bLength ? a : b, longer = aLength <= bLength ? b : a
            let chosen = bridge.extent == .short ? shorter : longer
            (t0, t1) = (chosen.stretch.low, chosen.stretch.high)
        case .none:
            (t0, t1) = (min(a.stretch.low, b.stretch.low) - width.value, max(a.stretch.high, b.stretch.high) + width.value)
        }
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

    /// The bridge between curved sheets' walls carried to their contacts (`CurvedSheetBridgeWalls`):
    /// each wall sewn anew, the bridge lofted between their contact edges continuous with them,
    /// and the walls Trim names joined with it in place of their sheets; the others stay as they
    /// were, the new walls only shaping the bridge.
    private func curvedBridge(_ bridge: SheetBridgeFeature, walls: (first: CurvedSheetBridgeWalls.Wall, second: CurvedSheetBridgeWalls.Wall),
                              feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult {
        let tolerance = context.tolerance
        func failure(_ code: KernelErrorCode, _ message: String) -> KernelError {
            KernelError(phase: .evaluation, code: code, featureID: feature.id, tolerance: tolerance, message: message)
        }
        var stages = FeatureEvaluationStages(context)
        var wallBodies: [BodyID] = []
        var contacts: [(source: FeatureID, edge: EdgeID)] = []
        for (ordinal, wall) in [walls.first, walls.second].enumerated() {
            let stageID = featureEvaluationStageID(featureID: feature.id, domain: .sheetBridgeTrim, ordinal: UInt64(20 + ordinal))
            let sewn = try sewer.sew(BRepSewingRequest(featureID: stageID, bodyKind: .sheet,
                shells: [BRepSewingShell(stableID: "\(wall.patch.stableID):shell", patches: [wall.patch])]), tolerance: tolerance)
            stages.apply(EvaluationResult(brep: try BRepModelCombiner().combined([stages.context.brep, sewn.brep]),
                                          subshapes: sewn.subshapes, lineage: sewn.lineage))
            wallBodies.append(sewn.bodyID)
            // The contact edge, found again by its middle.
            let scope = try BodyTopologyScope(bodyID: sewn.bodyID, model: stages.context.brep)
            let edge = try scope.references.compactMap { reference -> (EdgeID, Double)? in
                guard case let .edge(id) = reference, let edge = stages.context.brep.edges[id],
                      let curve = stages.context.brep.geometry.curves[edge.curveID], let trim = edge.trim else { return nil }
                let middle = try curve.point(at: (trim.startParameter + trim.endParameter) / 2, tolerance: tolerance)
                return (id, (middle - wall.contactMiddle).length)
            }.min { $0.1 < $1.1 }
            guard let edge, edge.1 <= tolerance.distance else {
                throw failure(.topologyFailure, "A Bridge Surface's wall lost its contact edge in sewing.")
            }
            contacts.append((stageID, edge.0))
        }
        let model = stages.context.brep
        func section(_ id: EdgeID, as featureID: FeatureID) throws -> EvaluatedCurve {
            guard let edge = model.edges[id], let exact = model.geometry.curves[edge.curveID], let trim = edge.trim else {
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
        let (sectionA, sectionB) = (try section(contacts[0].edge, as: curveA), try section(contacts[1].edge, as: curveB))
        guard let a0 = sectionA.points.first, let a1 = sectionA.points.last, let b0 = sectionB.points.first, let b1 = sectionB.points.last else {
            throw TopologyError.missingReference("A bridged edge has no points.")
        }
        let reversed = (a0 - b0).length + (a1 - b1).length > (a0 - b1).length + (a1 - b0).length
        var augmented = stages.context
        augmented.curves[curveA] = [sectionA]
        augmented.curves[curveB] = [sectionB]
        func continuity(_ source: FeatureID, _ edge: EdgeID) throws -> SurfaceEdgeContinuity? {
            guard bridge.shape == .curvature else { return nil }
            guard let subshapeID = augmented.subshapeIDs(for: .edge(edge)).first else {
                throw failure(.missingReference, "A bridged edge has no identity.")
            }
            let reference = StableSubshapeReference(subshapeID: subshapeID, geometrySignature: try SubshapeGeometrySignatureBuilder(
                model: model, tolerance: tolerance).signature(for: .edge(edge)))
            return SurfaceEdgeContinuity(source: source, bodyRole: .sheet, edge: reference, order: .curvature, tension: bridge.tension,
                                         angularAllowance: bridge.angularAllowance, curvatureAllowance: bridge.curvatureAllowance)
        }
        let loft = LoftFeature(sections: [
            LoftSectionReference(section: .curve(CurveSectionReference(featureID: curveA)), continuity: try continuity(contacts[0].source, contacts[0].edge)),
            LoftSectionReference(section: .curve(CurveSectionReference(featureID: curveB, isReversed: reversed)),
                                 continuity: try continuity(contacts[1].source, contacts[1].edge)),
        ], options: LoftOptions(resultKind: .sheet))
        let trims: [Bool] = switch bridge.trimWalls {
        case .none: [false, false]
        case .both: [true, true]
        case .first: [true, false]
        case .second: [false, true]
        }
        let originalsAndWalls = wallBodies
        guard trims.contains(true) else {
            // No wall trimmed: the bridge alone, under the feature, beside the sheets as they were.
            let lofted = try LoftFeatureEvaluator(sewer: sewer).evaluate(feature: FeatureNode(id: feature.id, operation: .loft(loft)),
                                                                         context: augmented)
            let kept = try BRepBodySubmodelExtractor().extract(
                bodyIDs: Set(lofted.brep.bodies.keys).subtracting(originalsAndWalls), from: lofted.brep)
            let removed = try originalsAndWalls.reduce(into: Set<SubshapeID>()) { result, bodyID in
                result.formUnion(try BodyTopologyScope(bodyID: bodyID, model: stages.context.brep).subshapeIDs(in: stages.context.subshapes))
            }
            return try stages.publish(EvaluationResult(brep: kept, subshapes: lofted.subshapes, removedSubshapeIDs: removed,
                                                       lineage: lofted.lineage), featureID: feature.id)
        }
        let bridgeStage = featureEvaluationStageID(featureID: feature.id, domain: .sheetBridgeTrim, ordinal: 2)
        let lofted = try LoftFeatureEvaluator(sewer: sewer).evaluate(feature: FeatureNode(id: bridgeStage, operation: .loft(loft)),
                                                                     context: augmented)
        stages.apply(lofted)
        let bridgeBody = try stages.publishedBody(of: lofted, featureID: feature.id, what: "Bridging curved sheets")
        let originals = [try context.bodyID(generatedBy: bridge.first), try context.bodyID(generatedBy: bridge.second)]
        // The new walls Trim does not name only shaped the bridge; their sheets stay.
        let dropped = zip(trims, wallBodies).filter { $0.0 == false }.map(\.1)
        let joined = zip(trims, wallBodies).filter(\.0).map(\.1) + [bridgeBody]
        let replacedOriginals = zip(trims, originals).filter(\.0).map(\.1)
        var current = try BRepBodySubmodelExtractor().extract(
            bodyIDs: Set(stages.context.brep.bodies.keys).subtracting(dropped + replacedOriginals), from: stages.context.brep)
        var removed = try (dropped + replacedOriginals).reduce(into: Set<SubshapeID>()) { result, bodyID in
            result.formUnion(try BodyTopologyScope(bodyID: bodyID, model: stages.context.brep).subshapeIDs(in: stages.context.subshapes))
        }
        var joinContext = stages.context
        joinContext.brep = current
        joinContext.validatedBRep = nil
        guard let joiner else { throw failure(.unsupportedCapability, "This evaluator cannot join a Bridge Surface with its walls.") }
        let sewn = try joiner.joinSheets(bodyIDs: joined, closed: false, featureID: feature.id, context: joinContext)
        removed.formUnion(try joined.reduce(into: Set<SubshapeID>()) { result, bodyID in
            result.formUnion(try BodyTopologyScope(bodyID: bodyID, model: current).subshapeIDs(in: stages.context.subshapes))
        })
        current = try BRepBodyModelReplacer().replacing(bodyIDs: Set(joined), with: sewn.brep, in: current)
        return try stages.publish(EvaluationResult(brep: current, subshapes: sewn.subshapes, removedSubshapeIDs: removed,
                                                   lineage: sewn.lineage), featureID: feature.id)
    }

    /// The bridge between a boundary edge of each sheet — the named ones, or the pair nearest each
    /// other — lofted between them, continuous with both sheets there: curvature continuous (G2,
    /// with the tension) or a straight chamfer (G0). The sheets stay as they are; Trim walls joins
    /// the walls it names with the bridge into one sheet (there is nothing past their edges to cut).
    private func edgeBridge(_ bridge: SheetBridgeFeature, feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult {
        let tolerance = context.tolerance
        func failure(_ code: KernelErrorCode, _ message: String) -> KernelError {
            KernelError(phase: .evaluation, code: code, featureID: feature.id, tolerance: tolerance, message: message)
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
        // The pairs bridged: the two edges, or with Propagate both sheets' tangent chains through
        // them, pair by pair in step.
        let pairs = bridge.propagates
            ? try propagatedPairs(firstEdge, secondEdge, first: try boundaryEdges(bridge.first), second: try boundaryEdges(bridge.second),
                                  context: context, failure: failure)
            : [(firstEdge, secondEdge)]
        var augmented = context
        /// The Loft between one pair: each edge a curve section, the second run the way the first does.
        func pairLoft(_ pair: (EdgeID, EdgeID), ordinal: UInt64) throws -> LoftFeature {
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
            let (curveA, curveB) = (featureEvaluationStageID(featureID: feature.id, domain: .sheetBridgeTrim, ordinal: 10 + 2 * ordinal),
                                    featureEvaluationStageID(featureID: feature.id, domain: .sheetBridgeTrim, ordinal: 11 + 2 * ordinal))
            let (sectionA, sectionB) = (try curve(pair.0, as: curveA), try curve(pair.1, as: curveB))
            guard let a0 = sectionA.points.first, let a1 = sectionA.points.last, let b0 = sectionB.points.first, let b1 = sectionB.points.last else {
                throw TopologyError.missingReference("A bridged edge has no points.")
            }
            let reversed = (a0 - b0).length + (a1 - b1).length > (a0 - b1).length + (a1 - b0).length
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
            return LoftFeature(sections: [
                LoftSectionReference(section: .curve(CurveSectionReference(featureID: curveA)), continuity: try continuity(bridge.first, pair.0)),
                LoftSectionReference(section: .curve(CurveSectionReference(featureID: curveB, isReversed: reversed)),
                                     continuity: try continuity(bridge.second, pair.1)),
            ], options: LoftOptions(resultKind: .sheet))
        }
        let lofts = try pairs.enumerated().map { index, pair in try pairLoft(pair, ordinal: UInt64(index)) }
        let loft = lofts[0]
        let walls: [FeatureID] = switch bridge.trimWalls {
        case .none: []
        case .both: [bridge.first, bridge.second]
        case .first: [bridge.first]
        case .second: [bridge.second]
        }
        guard walls.isEmpty == false || lofts.count > 1 else {
            return try LoftFeatureEvaluator(sewer: sewer).evaluate(feature: FeatureNode(id: feature.id, operation: .loft(loft)), context: augmented)
        }
        // Trim walls between boundary edges: the bridge starts on each sheet's own edge, so nothing
        // of a wall is cut away; the bridge is joined with the walls Trim names into one sheet.
        guard let joiner else {
            throw failure(.unsupportedCapability, "This evaluator cannot join a Bridge Surface with its walls.")
        }
        var stages = FeatureEvaluationStages(augmented)
        var joined = try walls.map { try context.bodyID(generatedBy: $0) }
        // Each pair's bridge a stage of its own (the first at the original ordinal), all joined.
        for (index, pairBridge) in lofts.enumerated() {
            let bridgeStage = featureEvaluationStageID(featureID: feature.id, domain: .sheetBridgeTrim,
                                                       ordinal: index == 0 ? 2 : 100 + UInt64(index))
            let lofted = try LoftFeatureEvaluator(sewer: sewer).evaluate(feature: FeatureNode(id: bridgeStage, operation: .loft(pairBridge)),
                                                                         context: stages.context)
            stages.apply(lofted)
            joined.append(try stages.publishedBody(of: lofted, featureID: feature.id, what: "Bridging boundary edges"))
        }
        let sewn = try joiner.joinSheets(bodyIDs: joined, closed: false, featureID: feature.id, context: stages.context)
        let replaced = try joined.reduce(into: Set<SubshapeID>()) { result, bodyID in
            result.formUnion(try BodyTopologyScope(bodyID: bodyID, model: stages.context.brep).subshapeIDs(in: stages.context.subshapes))
        }
        let model = try BRepBodyModelReplacer().replacing(bodyIDs: Set(joined), with: sewn.brep, in: stages.context.brep)
        return try stages.publish(EvaluationResult(brep: model, subshapes: sewn.subshapes,
                                                   removedSubshapeIDs: replaced, lineage: sewn.lineage), featureID: feature.id)
    }

    /// Propagate: the pairs of boundary edges through `seed`, each sheet's chain of boundary edges
    /// meeting tangentially walked from it both ways, the two chains paired in step (the second
    /// walked the way it runs beside the first) as far as both go.
    private func propagatedPairs(_ first: EdgeID, _ second: EdgeID, first firstBoundary: [EdgeID], second secondBoundary: [EdgeID],
                                 context: EvaluationContext, failure: (KernelErrorCode, String) -> KernelError) throws -> [(EdgeID, EdgeID)] {
        let tolerance = context.tolerance
        let model = context.brep
        /// An edge's end points and unit tangents there, along its vertices' order.
        func run(_ id: EdgeID) throws -> (start: VertexID, end: VertexID, startTangent: Vector3D, endTangent: Vector3D) {
            guard let edge = model.edges[id], let curve = model.geometry.curves[edge.curveID], let trim = edge.trim else {
                throw TopologyError.missingReference("A bridged edge is missing.")
            }
            let sense: Double = trim.endParameter >= trim.startParameter ? 1 : -1
            let at = { (t: Double) throws -> Vector3D in
                try (curve.differentialGeometry(at: t, tolerance: tolerance).firstDerivative * sense).normalized(tolerance: tolerance.distance)
            }
            return (edge.startVertexID, edge.endVertexID, try at(trim.startParameter), try at(trim.endParameter))
        }
        /// The chain through `seed` on a sheet's boundary, in the seed's own direction, and the
        /// seed's place in it.
        func chain(_ seed: EdgeID, _ boundary: [EdgeID]) throws -> (edges: [EdgeID], seedIndex: Int) {
            var byVertex: [VertexID: [EdgeID]] = [:]
            for id in boundary {
                let r = try run(id)
                byVertex[r.start, default: []].append(id)
                byVertex[r.end, default: []].append(id)
            }
            /// The next edge on from `edge` past its `atEnd` end, when it meets it tangentially.
            func next(_ edge: EdgeID, atEnd: Bool) throws -> (EdgeID, Bool)? {
                let r = try run(edge)
                let vertex = atEnd ? r.end : r.start
                let leaving = atEnd ? r.endTangent : r.startTangent * -1
                guard let others = byVertex[vertex]?.filter({ $0 != edge }), others.count == 1, let other = others.first else { return nil }
                let o = try run(other)
                // Walking on, the other edge leaves the vertex from its start or its end.
                let fromStart = o.start == vertex
                let onward = fromStart ? o.startTangent : o.endTangent * -1
                guard leaving.dot(onward) >= cos(tolerance.angle * 1000) else { return nil }
                return (other, fromStart)
            }
            var forward: [EdgeID] = [], backward: [EdgeID] = []
            var (edge, atEnd) = (seed, true)
            while let (other, fromStart) = try next(edge, atEnd: atEnd), other != seed, forward.contains(other) == false {
                forward.append(other)
                (edge, atEnd) = (other, fromStart)
            }
            (edge, atEnd) = (seed, false)
            while let (other, fromStart) = try next(edge, atEnd: atEnd), other != seed,
                  backward.contains(other) == false, forward.contains(other) == false {
                backward.append(other)
                (edge, atEnd) = (other, fromStart)
            }
            return (backward.reversed() + [seed] + forward, backward.count)
        }
        let a = try chain(first, firstBoundary)
        var b = try chain(second, secondBoundary)
        // The second chain runs the way the first does when its seed's start lies by the first's.
        let (ra, rb) = (try run(first), try run(second))
        func point(_ v: VertexID) throws -> Point3D {
            guard let p = model.vertices[v]?.point else { throw TopologyError.missingReference("A bridged vertex is missing.") }
            return p
        }
        let along = (try point(ra.start) - point(rb.start)).length + (try point(ra.end) - point(rb.end)).length
        let across = (try point(ra.start) - point(rb.end)).length + (try point(ra.end) - point(rb.start)).length
        if across < along { b = (b.edges.reversed(), b.edges.count - 1 - b.seedIndex) }
        let before = min(a.seedIndex, b.seedIndex)
        let after = min(a.edges.count - 1 - a.seedIndex, b.edges.count - 1 - b.seedIndex)
        guard before + after >= 0 else { throw failure(.invalidInput, "A propagated bridge has no pair of edges.") }
        return (-before...after).map { (a.edges[a.seedIndex + $0], b.edges[b.seedIndex + $0]) }
    }
}
