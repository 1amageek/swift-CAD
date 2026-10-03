import Foundation
import CADCore
import CADGeometry
import CADIR
import CADTopology

/// Match Face: the matched faces take the reference face's surface, placed in the target's frame,
/// and the faces around them are re-solved to meet them (`FaceSurfaceReplacementRebuilder`).
public struct FaceMatchFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    private let subshapeResolver: any StableSubshapeResolving
    private let identityBuilder: any CarriedTopologyIdentityBuilding
    /// Push Face, which a match of one planar face onto a parallel plane facing the same way is:
    /// its Grow then runs into walls as Push Face's does.
    private let pusher: (any FeatureEvaluating)?

    public init(subshapeResolver: any StableSubshapeResolving = StableSubshapeResolver(), pusher: (any FeatureEvaluating)? = nil) {
        self.subshapeResolver = subshapeResolver
        self.pusher = pusher
        identityBuilder = DefaultCarriedTopologyIdentityBuilder()
    }

    public func evaluate(feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult {
        try evaluateValidated(feature: feature, context: context).result
    }

    package func evaluateValidated(feature: FeatureNode, context: EvaluationContext) throws -> ValidatedFeatureEvaluation {
        try FeatureEvaluationBoundary.evaluateValidated(featureID: feature.id, tolerance: context.tolerance) {
            try evaluateFaceMatch(feature: feature, context: context)
        }
    }

    private func evaluateFaceMatch(feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult {
        guard case let .faceMatch(match) = feature.operation else {
            throw failure(.invalidInput, feature.id, context.tolerance, "Match Face evaluator requires a faceMatch feature.")
        }
        try FeatureEvaluationBoundary.validateRequest(featureID: feature.id, tolerance: context.tolerance) {
            try match.validate()
        }
        try FeatureEvaluationBoundary.validateExactInput(context, featureID: feature.id, tolerance: context.tolerance)
        let tolerance = context.tolerance
        let bodyID = try context.bodyID(generatedBy: match.target.featureID)
        let bodyScope = try BodyTopologyScope(bodyID: bodyID, model: context.brep)
        let sourceBodyID = try context.bodyID(generatedBy: match.source.featureID)
        let sourceScope = try BodyTopologyScope(bodyID: sourceBodyID, model: context.brep)
        let faceIDs = try match.faces.map { try faceID($0, in: bodyScope, featureID: feature.id, context: context) }
        guard Set(faceIDs).count == faceIDs.count else {
            throw failure(.invalidInput, feature.id, tolerance, "Match Face selections resolve to the same face.")
        }
        let referenceID = try faceID(match.referenceFace, in: sourceScope, featureID: feature.id, context: context)
        guard faceIDs.contains(referenceID) == false else {
            throw failure(.invalidInput, feature.id, tolerance, "Match Face cannot match a face to itself.")
        }
        var model = context.brep
        guard let reference = model.faces[referenceID], var surface = model.geometry.surfaces[reference.surfaceID] else {
            throw TopologyError.missingReference("Match Face reference face is missing.")
        }
        if let placement = match.sourcePlacement {
            surface = try placement.applying(to: surface, tolerance: tolerance)
        }
        let feet = SurfaceFootResolver()
        var replacements: [FaceID: FaceSurfaceReplacementRebuilder.Replacement] = [:]
        // Where each face lies and lands: its centre, its outward side and the reference's point it reaches.
        var reaches: [FaceID: (center: Point3D, outward: Vector3D, landed: Point3D)] = [:]
        for faceID in faceIDs {
            guard let face = model.faces[faceID], let previous = model.geometry.surfaces[face.surfaceID] else {
                throw TopologyError.missingReference("Match Face face is missing.")
            }
            let points = try face.loops.flatMap { try model.orderedPoints(for: $0) }
            guard points.isEmpty == false else {
                throw failure(.unsupportedCapability, feature.id, tolerance, "A matched face has no vertices to place it by.")
            }
            let center = Point3D.origin + points.reduce(Vector3D.zero) { $0 + ($1 - .origin) } / Double(points.count)
            let near = try feet.foot(of: center, on: surface, tolerance: tolerance)
            let before = try feet.foot(of: center, on: previous, tolerance: tolerance).normal
            let outward = face.orientation == .forward ? before : before * -1
            let orientation: Orientation
            var landing = Vector3D.zero
            if match.front {
                // Side: the reference face's front, its outward side (which a mirroring placement
                // turns to the surface's other side). The face lands where that front faces the
                // way the face did: past a closed reference's near side, on its far side.
                let flips = match.sourcePlacement?.reversesOrientation ?? false
                orientation = (reference.orientation == .forward) != flips ? .forward : .reversed
                let front = orientation == .forward ? near.normal : near.normal * -1
                if front.dot(outward) <= 0 {
                    let extent = try referenceExtent(reference, model: model) + (center - near.point).length
                    let reached = try landingPoint(from: center, along: outward, on: surface, orientation: orientation,
                                                   within: extent, featureID: feature.id, tolerance: tolerance)
                    landing = reached - near.point
                }
            } else {
                orientation = near.normal.dot(outward) > 0 ? .forward : .reversed
            }
            replacements[faceID] = FaceSurfaceReplacementRebuilder.Replacement(surface: surface, orientation: orientation, landing: landing)
            reaches[faceID] = (center, try outward.normalized(tolerance: tolerance.distance), near.point + landing)
        }
        // One planar face onto a parallel plane, facing the same way: a push by the planes' distance.
        if let pusher, faceIDs.count == 1, let face = model.faces[faceIDs[0]], let previous = model.geometry.surfaces[face.surfaceID],
           let replacement = replacements[faceIDs[0]], let distance = try parallelPush(from: previous, orientation: face.orientation,
                                                                                       onto: replacement, tolerance: tolerance) {
            let push = FeatureNode(id: feature.id, name: feature.name, operation: .faceOffset(FaceOffsetFeature(
                target: FaceOffsetTargetReference(featureID: match.target.featureID), faces: match.faces,
                distance: .constant(.length(distance, unit: .meter)), grow: match.grow
            )), outputs: feature.outputs)
            return try pusher.evaluate(feature: push, context: context)
        }
        do {
            try FaceSurfaceReplacementRebuilder().replace(replacements, bodyID: bodyID, featureID: feature.id, model: &model, tolerance: tolerance)
        } catch let error as KernelError where error.code == .topologyFailure {
            // One planar face running into another wall on its way out to a curved reference:
            // Push Face's Grow carries it out to where it reaches the reference (Fixed stopping
            // at the wall), then the face it ends on — the wall it carried (Moving) or its own
            // bar's end (None) — takes the reference's surface in place.
            // FIXME(INCOMPLETE_IMPLEMENTATION): several matched faces, a curved matched face, or
            // one running into a wall inward still refuse here. Production path:
            // FaceMatchFeatureEvaluator. Complete only when those grow too, verified by a pair of
            // faces matched past a wall.
            guard let pusher, faceIDs.count == 1, let reach = reaches[faceIDs[0]], let replacement = replacements[faceIDs[0]],
                  let face = context.brep.faces[faceIDs[0]], let previous = context.brep.geometry.surfaces[face.surfaceID],
                  try DefaultPlanarSurfaceResolver().exactPlane(for: previous, tolerance: tolerance) != nil else { throw error }
            let distance = (reach.landed - reach.center).dot(reach.outward)
            guard distance > tolerance.distance else { throw error }
            return try grown(match, feature: feature, by: distance, outward: reach.outward, center: reach.center,
                             onto: replacement, pusher: pusher, context: context)
        }
        try ExactFacePcurveBuilder().populateMissingPcurves(in: &model, tolerance: tolerance)
        let isSolid = model.bodies[bodyID]?.kind == .solid
        try model.validate(level: isSolid ? .volumetric : .exact, tolerance: tolerance)
        let identity = try identityBuilder.identity(featureID: feature.id, bodyID: bodyID, model: model, context: context)
        return EvaluationResult(
            brep: model,
            subshapes: identity.subshapes,
            removedSubshapeIDs: bodyScope.subshapeIDs(in: context.subshapes),
            lineage: identity.lineage
        )
    }

    /// Match Face's Grow past a wall: Push Face carries the face out by `distance` under the
    /// match's Grow; unless Fixed stops it at the wall, the face it ends on, on the plane that far
    /// out facing the same way, takes the reference's surface and the faces around re-solve.
    private func grown(_ match: FaceMatchFeature, feature: FeatureNode, by distance: Double, outward: Vector3D, center: Point3D,
                       onto replacement: FaceSurfaceReplacementRebuilder.Replacement, pusher: any FeatureEvaluating,
                       context: EvaluationContext) throws -> EvaluationResult {
        let tolerance = context.tolerance
        let push = FeatureNode(id: feature.id, name: feature.name, operation: .faceOffset(FaceOffsetFeature(
            target: FaceOffsetTargetReference(featureID: match.target.featureID), faces: match.faces,
            distance: .constant(.length(distance, unit: .meter)), grow: match.grow
        )), outputs: feature.outputs)
        let pushed = try pusher.evaluate(feature: push, context: context)
        guard match.grow != .fixed else { return pushed }
        var model = pushed.brep
        guard let bodyID = pushed.subshapes.compactMap({ key, value -> BodyID? in
            guard key.featureID == feature.id, case let .body(id) = value else { return nil }
            return id
        }).first else {
            throw TopologyError.missingReference("Match Face's grown body is missing.")
        }
        let planes = DefaultPlanarSurfaceResolver()
        var ends: [FaceID: FaceSurfaceReplacementRebuilder.Replacement] = [:]
        for case let .face(faceID) in try BodyTopologyScope(bodyID: bodyID, model: model).references {
            guard let face = model.faces[faceID], let surface = model.geometry.surfaces[face.surfaceID],
                  let plane = try planes.exactPlane(for: surface, tolerance: tolerance) else { continue }
            let normal = try plane.normal.normalized(tolerance: tolerance.distance) * (face.orientation == .forward ? 1 : -1)
            guard normal.dot(outward) >= 1 - tolerance.angle,
                  abs((plane.origin - center).dot(outward) - distance) <= tolerance.distance else { continue }
            ends[faceID] = FaceSurfaceReplacementRebuilder.Replacement(surface: replacement.surface, orientation: replacement.orientation)
        }
        guard ends.isEmpty == false else {
            throw failure(.topologyFailure, feature.id, tolerance, "Match Face's grown face did not reach the reference.")
        }
        try FaceSurfaceReplacementRebuilder().replace(ends, bodyID: bodyID, featureID: feature.id, model: &model, tolerance: tolerance)
        try ExactFacePcurveBuilder().populateMissingPcurves(in: &model, tolerance: tolerance)
        try model.validate(level: model.bodies[bodyID]?.kind == .solid ? .volumetric : .exact, tolerance: tolerance)
        let identity = try identityBuilder.identity(featureID: feature.id, bodyID: bodyID, model: model, context: context)
        return EvaluationResult(brep: model, subshapes: identity.subshapes, removedSubshapeIDs: pushed.removedSubshapeIDs,
                                lineage: identity.lineage)
    }

    /// The diagonal of the box around the reference face's boundary points, which bounds how far
    /// along a line the face's surface can still be met.
    private func referenceExtent(_ reference: Face, model: BRepModel) throws -> Double {
        let points = try reference.loops.flatMap { try model.orderedPoints(for: $0) }
        guard let first = points.first else { return 0 }
        var low = first, high = first
        for point in points {
            low = Point3D(x: min(low.x, point.x), y: min(low.y, point.y), z: min(low.z, point.z))
            high = Point3D(x: max(high.x, point.x), y: max(high.y, point.y), z: max(high.z, point.z))
        }
        return (high - low).length
    }

    /// Where the line through `center` along `direction` meets `surface` with the face's front,
    /// oriented by `orientation`, facing along `direction`, nearest `center` within `extent` either
    /// way: the crossings are bracketed by the sign of the point's distance from the surface and
    /// refined on the line.
    private func landingPoint(from center: Point3D, along direction: Vector3D, on surface: Surface3D, orientation: Orientation,
                              within extent: Double, featureID: FeatureID, tolerance: ModelingTolerance) throws -> Point3D {
        let solver = BRepSurfaceMeetingSolver(tolerance: tolerance)
        let unit = try direction.normalized(tolerance: tolerance.distance)
        let line = Curve3D.line(Line3D(origin: center, direction: unit))
        let reach = max(extent, tolerance.distance) * 2
        let steps = 256
        func signedDistance(_ t: Double) throws -> Double {
            let point = center + unit * t
            let foot = try solver.foot(of: point, on: surface)
            return (point - foot.point).dot(foot.normal)
        }
        var best: (point: Point3D, distance: Double)?
        var previous = (t: -reach, value: try signedDistance(-reach))
        for step in 1...steps {
            let t = -reach + 2 * reach * Double(step) / Double(steps)
            let value = try signedDistance(t)
            defer { previous = (t, value) }
            guard (previous.value <= 0) != (value <= 0) else { continue }
            let seed = center + unit * ((previous.t + t) / 2)
            guard let crossing = try solver.crossingPoint(on: line, with: [surface], near: seed) else { continue }
            let normal = try solver.foot(of: crossing, on: surface).normal
            let front = orientation == .forward ? normal : normal * -1
            guard front.dot(unit) > 0 else { continue }
            let distance = (crossing - center).length
            if best.map({ distance < $0.distance }) ?? true { best = (crossing, distance) }
        }
        guard let best else {
            throw failure(.topologyFailure, featureID, tolerance, "Match Face's Side finds no part of the reference facing the way the face does.")
        }
        return best.point
    }

    /// How far a planar face moves along its outward side onto a parallel plane facing the same
    /// way; nil for any other match.
    private func parallelPush(from previous: Surface3D, orientation: Orientation, onto replacement: FaceSurfaceReplacementRebuilder.Replacement,
                              tolerance: ModelingTolerance) throws -> Double? {
        let planes = DefaultPlanarSurfaceResolver()
        guard let old = try planes.exactPlane(for: previous, tolerance: tolerance),
              let new = try planes.exactPlane(for: replacement.surface, tolerance: tolerance) else { return nil }
        let outward = try old.normal.normalized(tolerance: tolerance.distance) * (orientation == .forward ? 1 : -1)
        let newOutward = try new.normal.normalized(tolerance: tolerance.distance) * (replacement.orientation == .forward ? 1 : -1)
        guard newOutward.dot(outward) >= 1 - tolerance.angle else { return nil }
        let distance = (new.origin - old.origin).dot(outward)
        return abs(distance) > tolerance.distance ? distance : nil
    }

    private func faceID(
        _ stableReference: StableSubshapeReference,
        in scope: BodyTopologyScope,
        featureID: FeatureID,
        context: EvaluationContext
    ) throws -> FaceID {
        let reference = try subshapeResolver.topologyReference(
            for: stableReference, model: context.brep, subshapes: context.subshapes,
            lineage: context.lineage, tolerance: context.tolerance
        )
        guard case let .face(faceID) = reference, scope.references.contains(.face(faceID)) else {
            throw KernelError(
                phase: .evaluation, code: .missingReference, featureID: featureID, subshapeID: stableReference.subshapeID,
                tolerance: context.tolerance, message: "A Match Face selection did not resolve to a face of its body."
            )
        }
        return faceID
    }

    private func failure(_ code: KernelErrorCode, _ featureID: FeatureID, _ tolerance: ModelingTolerance, _ message: String) -> KernelError {
        KernelError(phase: code == .topologyFailure ? .topology : .evaluation, code: code, featureID: featureID, tolerance: tolerance, message: message)
    }
}
