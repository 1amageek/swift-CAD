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

    private struct Sheet {
        let bodyID: BodyID
        let normal: Vector3D
        let origin: Point3D
        let points: [Point3D]
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
        // Each sheet: one planar face, its plane and its vertices.
        func sheet(_ featureID: FeatureID) throws -> Sheet {
            let bodyID = try context.bodyID(generatedBy: featureID)
            let scope = try BodyTopologyScope(bodyID: bodyID, model: context.brep)
            let faces = scope.references.compactMap { reference -> FaceID? in
                if case let .face(id) = reference { return id }
                return nil
            }
            guard faces.count == 1, let face = context.brep.faces[faces[0]],
                  let surface = context.brep.geometry.surfaces[face.surfaceID],
                  let plane = try DefaultPlanarSurfaceResolver().exactPlane(for: surface, tolerance: tolerance) else {
                // FIXME(INCOMPLETE_IMPLEMENTATION): a bridge between curved or many-faced sheets
                // needs contact curves at the width along curved faces and their continuity
                // rows, which are not built, so only single planar faces are bridged. Production
                // path: SheetBridgeFeatureEvaluator. Complete only when curved sheets are bridged
                // within a stated allowance, verified by a bridge between two cylinders.
                throw failure(.unsupportedCapability, "A Bridge Surface joins two single-face planar sheets.")
            }
            let points = scope.references.compactMap { reference -> Point3D? in
                if case let .vertex(id) = reference { return context.brep.vertices[id]?.point }
                return nil
            }
            return Sheet(bodyID: bodyID, normal: try plane.normal.normalized(tolerance: tolerance.distance), origin: plane.origin, points: points)
        }
        let a = try sheet(bridge.first), b = try sheet(bridge.second)
        let along = a.normal.cross(b.normal)
        guard along.length > tolerance.angle else {
            throw failure(.unsupportedCapability, "A Bridge Surface joins sheets whose planes meet; these are parallel.")
        }
        let d = try along.normalized(tolerance: tolerance.distance)
        // A point of both planes: the combination of their normals meeting each plane's offset.
        let (c1, c2) = (a.normal.dot(a.origin - .origin), b.normal.dot(b.origin - .origin))
        let cosine = a.normal.dot(b.normal)
        let determinant = 1 - cosine * cosine
        let lineOrigin = Point3D.origin + a.normal * ((c1 - c2 * cosine) / determinant) + b.normal * ((c2 - c1 * cosine) / determinant)
        // Each sheet's direction away from the line in its plane, toward the sheet (or by sense
        // for a sheet crossing it), and its stretch along the line.
        func away(_ sheet: Sheet) throws -> Vector3D {
            let direction = try sheet.normal.cross(d).normalized(tolerance: tolerance.distance)
            let distances = sheet.points.map { ($0 - lineOrigin).dot(direction) }
            guard let low = distances.min(), let high = distances.max() else { throw failure(.invalidInput, "A bridged sheet has no vertices.") }
            let side: Double
            if low >= -tolerance.distance { side = 1 }
            else if high <= tolerance.distance { side = -1 }
            else { side = bridge.reversesSense ? -1 : 1 }
            guard (side > 0 ? high : -low) >= width.value - tolerance.distance else {
                throw failure(.invalidInput, "A bridged sheet does not reach the bridge's width from where the sheets meet.")
            }
            return direction * side
        }
        let m1 = try away(a), m2 = try away(b)
        func stretch(_ sheet: Sheet) -> (Double, Double) {
            let values = sheet.points.map { ($0 - lineOrigin).dot(d) }
            return (values.min() ?? 0, values.max() ?? 0)
        }
        let (a0, a1) = stretch(a), (b0, b1) = stretch(b)
        let (t0, t1) = (max(a0, b0), min(a1, b1))
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
        // Which walls are trimmed: both, or the one reaching less (Short) or more (Long) far from L.
        func reach(_ sheet: Sheet, _ away: Vector3D) -> Double {
            sheet.points.map { ($0 - lineOrigin).dot(away) }.max() ?? 0
        }
        let trimmed: [(Sheet, Point3D, Vector3D)]
        switch bridge.trimWalls {
        case .none: trimmed = []
        case .both: trimmed = [(a, p1, m1), (b, p2, m2)]
        case .short: trimmed = reach(a, m1) <= reach(b, m2) ? [(a, p1, m1)] : [(b, p2, m2)]
        case .long: trimmed = reach(a, m1) > reach(b, m2) ? [(a, p1, m1)] : [(b, p2, m2)]
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
        // A trimmed wall meets the bridge along its whole contact line only where it covers the
        // bridge's stretch exactly.
        for (sheet, _, _) in trimmed {
            let (s0, s1) = stretch(sheet)
            guard abs(s0 - t0) <= tolerance.distance, abs(s1 - t1) <= tolerance.distance else {
                // FIXME(INCOMPLETE_IMPLEMENTATION): a trimmed wall longer than the bridge meets it
                // along part of its cut edge, which joining by whole edges does not sew, so it is
                // refused. Production path: SheetBridgeFeatureEvaluator for trimmed walls.
                // Complete only when the cut edge is split at the bridge's ends, verified by a
                // trimmed bridge between sheets of different lengths.
                throw failure(.unsupportedCapability, "A trimmed wall covers exactly the bridge's stretch along where the sheets meet.")
            }
        }
        // Stages: each trimmed wall cut at its contact line keeping the side away from L, then the
        // bridge beside them; all joined into the feature's one sheet.
        var stages = FeatureEvaluationStages(context)
        var joined: [BodyID] = []
        for (ordinal, (sheet, contact, away)) in trimmed.enumerated() {
            let stageID = featureEvaluationStageID(featureID: feature.id, domain: .sheetBridgeTrim, ordinal: UInt64(ordinal))
            guard let cut = try cutter.cut(bodyID: sheet.bodyID, planeOrigin: contact, planeNormal: away * -1,
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
