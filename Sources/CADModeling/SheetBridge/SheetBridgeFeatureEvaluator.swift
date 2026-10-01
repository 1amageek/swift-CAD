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
}
