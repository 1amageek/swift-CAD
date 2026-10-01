import Foundation
import CADCore
import CADGeometry
import CADIR
import CADTopology

/// Bridge Surface between two planar sheets: the planes' meeting line L, each sheet's direction
/// away from L in its plane, the contact lines `width` along them, and the bridge swept along L
/// over the stretch both sheets cover: a quintic whose first and last three control points lie on
/// the sheets' planes (tangent and curvature continuous with them) or a straight chamfer.
public struct SheetBridgeFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    private let sewer: any BRepSewing
    private let resolver: ParameterResolving

    public init(sewer: any BRepSewing, resolver: ParameterResolving = ParameterResolver()) {
        self.sewer = sewer
        self.resolver = resolver
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
        guard bridge.trimWalls == .none else {
            // FIXME(INCOMPLETE_IMPLEMENTATION): trimming the sheets back to the bridge's contacts
            // replaces them with cut sheets in the same result, which this evaluator does not
            // compose, so Trim walls other than None are refused. Production path:
            // SheetBridgeFeatureEvaluator for every Bridge Surface. Complete only when the cut
            // sheets and the bridge are published together, verified by a Both-trimmed bridge.
            throw failure(.unsupportedCapability, "Bridge Surface trims no walls yet.")
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
            return Sheet(normal: try plane.normal.normalized(tolerance: tolerance.distance), origin: plane.origin, points: points)
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
        let sewn = try sewer.sew(BRepSewingRequest(featureID: feature.id, bodyKind: .sheet,
            shells: [BRepSewingShell(stableID: "bridgeSurface:shell", patches: [patch])]), tolerance: tolerance)
        return EvaluationResult(brep: try BRepModelCombiner().combined([context.brep, sewn.brep]),
                                subshapes: sewn.subshapes, lineage: sewn.lineage)
    }
}
