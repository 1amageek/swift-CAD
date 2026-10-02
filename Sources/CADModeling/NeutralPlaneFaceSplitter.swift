import Foundation
import CADCore
import CADGeometry
import CADIR
import CADTopology

/// Draft Face's split of the planar faces that cross its neutral plane: each such face of one
/// outer loop is cut along the plane into the part above and the part below, its edges crossing
/// the plane split there and the faces beside them split at the same points
/// (`BRepSewingTJunctionSplitter`), and the body's faces sewn anew. Each part then drafts away
/// from the plane on its own side about the cut, which both parts keep.
package struct NeutralPlaneFaceSplitter {
    package struct Result {
        package let model: BRepModel
        package let bodyID: BodyID
        package let sewn: BRepSewingResult
        /// Each split face's parts and every other drafted face, by the stable keys of their patches.
        package let draftedFaces: [FaceID]
    }

    private let tolerance: ModelingTolerance

    package init(tolerance: ModelingTolerance) {
        self.tolerance = tolerance
    }

    package func split(
        _ crossing: Set<FaceID>, drafting: [FaceID], bodyID: BodyID, planeOrigin: Point3D, pull: Vector3D,
        model: BRepModel, sewer: any BRepSewing, featureID: FeatureID, sourceSubshapes: [SubshapeID: TopologyReference]
    ) throws -> Result {
        func failure(_ message: String) -> KernelError {
            KernelError(phase: .evaluation, code: .unsupportedCapability, featureID: featureID, tolerance: tolerance, message: message)
        }
        guard let body = model.bodies[bodyID], body.shellIDs.count == 1, let shell = model.shells[body.shellIDs[0]] else {
            throw failure("Face draft splits faces across the neutral plane of a body of one shell.")
        }
        func height(_ point: Point3D) -> Double { (point - planeOrigin).dot(pull) }
        var patches: [BRepSewingFacePatch] = []
        var draftedKeys: [String] = []
        for (index, faceID) in shell.faceIDs.enumerated() {
            let stableID = "draft:face:\(index)"
            let patch = try SourceBRepFacePatchBuilder().build(faceID: faceID, stableID: stableID, from: model,
                                                               sourceSubshapes: sourceSubshapes, tolerance: tolerance).patch
            guard crossing.contains(faceID) else {
                patches.append(patch)
                if drafting.contains(faceID) { draftedKeys.append(stableID) }
                continue
            }
            guard patch.loops.count == 1, let loop = patch.loops.first, try cutSupport(patch.surface, pull: pull) else {
                // FIXME(INCOMPLETE_IMPLEMENTATION): a face with holes, or on a surface other than a
                // plane or a cylinder along the pull, crossing the neutral plane would be cut along
                // its crossing with the plane, which is not built, so it is refused. Production
                // path: FaceDraftFeatureEvaluator through NeutralPlaneFaceSplitter. Complete only when
                // such faces are split and drafted, verified by a holed wall drafted across an offset
                // neutral plane.
                throw failure("Face draft splits planar and axial cylindrical faces of one loop across the neutral plane.")
            }
            // Edges crossing the plane split where they cross it.
            var edges: [BRepSewingEdge] = []
            for (k, edge) in loop.edges.enumerated() {
                let (h0, h1) = (height(edge.startPoint), height(edge.endPoint))
                guard h0 * h1 < 0, abs(h0) > tolerance.distance, abs(h1) > tolerance.distance else {
                    edges.append(edge)
                    continue
                }
                var (low, high) = (edge.startParameter, edge.endParameter)
                for _ in 0..<80 {
                    let middle = 0.5 * (low + high)
                    let h = height(try edge.curve.point(at: middle, tolerance: tolerance))
                    if (h < 0) == (h0 < 0) { low = middle } else { high = middle }
                }
                let at = 0.5 * (low + high)
                let point = try edge.curve.point(at: at, tolerance: tolerance)
                edges.append(try piece(of: edge, from: edge.startParameter, to: at, start: edge.startPoint, end: point,
                                       on: patch.surface, suffix: "\(k):0"))
                edges.append(try piece(of: edge, from: at, to: edge.endParameter, start: point, end: edge.endPoint,
                                       on: patch.surface, suffix: "\(k):1"))
            }
            // The loop's runs above and below the plane, meeting at two points on it.
            let sides = try edges.map { edge -> Double in
                height(try edge.curve.point(at: 0.5 * (edge.startParameter + edge.endParameter), tolerance: tolerance))
            }
            guard sides.allSatisfy({ abs($0) > tolerance.distance }) else {
                throw failure("Face draft cannot split a face with an edge lying on the neutral plane.")
            }
            // Rotate the loop to start where it rises above the plane.
            guard let first = sides.indices.first(where: { sides[$0] > 0 && sides[(($0 - 1) + sides.count) % sides.count] < 0 }) else {
                throw failure("Face draft splits a face the neutral plane crosses.")
            }
            let ordered = Array(edges[first...] + edges[..<first])
            let orderedSides = Array(sides[first...] + sides[..<first])
            guard let switchIndex = orderedSides.firstIndex(where: { $0 < 0 }),
                  orderedSides[switchIndex...].allSatisfy({ $0 < 0 }) else {
                // FIXME(INCOMPLETE_IMPLEMENTATION): a face the neutral plane crosses more than
                // twice would split into more than two parts, which is not built. Production path:
                // FaceDraftFeatureEvaluator through NeutralPlaneFaceSplitter. Complete only when such
                // faces are split, verified by a U-shaped wall drafted across its neutral plane.
                throw failure("Face draft splits a face the neutral plane crosses twice.")
            }
            let above = Array(ordered[..<switchIndex]), below = Array(ordered[switchIndex...])
            guard let aboveEnd = above.last?.endPoint, let aboveStart = above.first?.startPoint else {
                throw failure("Face draft lost a split face's run above the plane.")
            }
            let cut = try cutEdge(from: aboveEnd, to: aboveStart, on: patch.surface, stableID: "\(stableID):cut:above")
            let back = try cutEdge(from: aboveStart, to: aboveEnd, on: patch.surface, stableID: "\(stableID):cut:below")
            for (part, run, closing) in [("above", above, cut), ("below", below, back)] {
                let partID = "\(stableID):\(part)"
                patches.append(BRepSewingFacePatch(
                    stableID: partID, surface: patch.surface, orientation: patch.orientation,
                    loops: [BRepSewingLoop(stableID: "\(partID):outer", role: .outer, edges: run + [closing])],
                    parentSubshapeIDs: patch.parentSubshapeIDs
                ))
                draftedKeys.append(partID)
            }
        }
        let split = try BRepSewingTJunctionSplitter(tolerance: tolerance).split(patches)
        let sewn = try sewer.sew(BRepSewingRequest(featureID: featureID, bodyKind: body.kind == .sheet ? .sheet : .solid,
                                                   shells: [BRepSewingShell(stableID: "draft:shell", patches: split)]),
                                 tolerance: tolerance)
        let replaced = try BRepBodyModelReplacer().replacing(bodyID: bodyID, with: sewn.bodyID, from: sewn.brep, in: model)
        let faces = try draftedKeys.map { key -> FaceID in
            guard case let .face(faceID)? = sewn.stableReferences[.face(key)] else {
                throw TopologyError.missingReference("A drafted face was lost while splitting across the neutral plane.")
            }
            return faceID
        }
        return Result(model: replaced, bodyID: sewn.bodyID, sewn: sewn, draftedFaces: faces)
    }

    private func piece(of edge: BRepSewingEdge, from t0: Double, to t1: Double, start: Point3D, end: Point3D,
                       on surface: Surface3D, suffix: String) throws -> BRepSewingEdge {
        BRepSewingEdge(stableID: "\(edge.stableID):\(suffix)", curve: edge.curve, startParameter: t0, endParameter: t1,
                       startPoint: start, endPoint: end,
                       surfaceParameterCurve: try ExactFacePcurveBuilder().surfaceParameterCurve(
                           for: edge.curve, startParameter: t0, endParameter: t1, on: surface, tolerance: tolerance),
                       parentSubshapeIDs: edge.parentSubshapeIDs)
    }

    /// Whether a face on `surface` is cut along the plane square to `pull`: a plane (a line) or a
    /// cylinder whose axis runs along the pull (an arc).
    private func cutSupport(_ surface: Surface3D, pull: Vector3D) throws -> Bool {
        switch surface {
        case .plane: return true
        case let .cylinder(cylinder): return cylinder.axis.cross(pull).length <= tolerance.angle * max(cylinder.axis.length, 1)
        case let .analytic(.cylinder(_, axis, _)): return axis.cross(pull).length <= tolerance.angle * max(axis.length, 1)
        default: return false
        }
    }

    /// The cut across a face from `start` to `end` on the plane: a line on a plane; on a cylinder
    /// along the pull the arc of its circle there, the shorter way round (a face of half the
    /// cylinder or less).
    private func cutEdge(from start: Point3D, to end: Point3D, on surface: Surface3D, stableID: String) throws -> BRepSewingEdge {
        let (origin, axis, radius): (Point3D, Vector3D, Double)
        switch surface {
        case let .cylinder(cylinder): (origin, axis, radius) = (cylinder.origin, cylinder.axis, cylinder.radius)
        case let .analytic(.cylinder(o, a, r)): (origin, axis, radius) = (o, a, r)
        default: return try line(from: start, to: end, on: surface, stableID: stableID)
        }
        let unit = try axis.normalized(tolerance: tolerance.distance)
        let circle = Curve3D.circle(Circle3D(center: origin + unit * (start - origin).dot(unit), normal: unit, radius: radius))
        let t0 = try circle.parameterProjection(of: start, tolerance: tolerance).parameter
        var t1 = try circle.parameterProjection(of: end, tolerance: tolerance).parameter
        while t1 - t0 > Double.pi { t1 -= 2 * Double.pi }
        while t1 - t0 < -Double.pi { t1 += 2 * Double.pi }
        return BRepSewingEdge(stableID: stableID, curve: circle, startParameter: t0, endParameter: t1, startPoint: start, endPoint: end,
                              surfaceParameterCurve: try ExactFacePcurveBuilder().surfaceParameterCurve(
                                  for: circle, startParameter: t0, endParameter: t1, on: surface, tolerance: tolerance))
    }

    private func line(from start: Point3D, to end: Point3D, on surface: Surface3D, stableID: String) throws -> BRepSewingEdge {
        let delta = end - start
        let curve = Curve3D.line(Line3D(origin: start, direction: try delta.normalized(tolerance: tolerance.distance)))
        return BRepSewingEdge(stableID: stableID, curve: curve, startParameter: 0, endParameter: delta.length, startPoint: start, endPoint: end,
                              surfaceParameterCurve: try ExactFacePcurveBuilder().surfaceParameterCurve(
                                  for: curve, startParameter: 0, endParameter: delta.length, on: surface, tolerance: tolerance))
    }
}
