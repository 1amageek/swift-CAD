import Foundation
import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology

/// A revolved solid (a cylinder or cone frustum) standing on a planar face of another solid from
/// outside, its cap's disc inside that face clear of the face's edges, the face's plane bounding
/// the other solid (a boss on a plate, holes and all; a smaller cylinder stacked on a larger).
/// Their union keeps every face of both but the standing solid's cap: the face it stands on takes
/// the cap's boundary as a hole, those edges then bounding that hole and the standing solid's wall.
/// Standing flush on a coaxial revolved solid's cap of its own radius (two equal cylinders stacked),
/// both caps go and the two walls meet along their shared circle, each one's rim split where the
/// other's is.
struct StandingRevolvedUnionPlan: Sendable {
    let largerBodyID: BodyID
    let smallerBodyID: BodyID
    /// The face taking the hole.
    let annulusFaceID: FaceID
    /// The standing solid's cap that goes.
    let droppedFaceID: FaceID
    /// Whether the face stood on is a coaxial cap of the same radius, which goes too.
    let flush: Bool
    /// The shared circle's centre and radius when flush.
    let circle: (center: Point3D, radius: Double)

    /// The plan when either operand stands on the other so; nil for any other pair.
    init?(targetBodyID: BodyID, toolBodyID: BodyID, model: BRepModel, tolerance: ModelingTolerance) throws {
        for (larger, smaller) in [(targetBodyID, toolBodyID), (toolBodyID, targetBodyID)] {
            if let found = try Self.standing(smaller, on: larger, model: model, tolerance: tolerance) {
                largerBodyID = larger
                smallerBodyID = smaller
                annulusFaceID = found.face
                droppedFaceID = found.cap
                flush = found.flush
                circle = found.circle
                return
            }
        }
        return nil
    }

    /// The face of `larger` the revolved `smaller` stands on and `smaller`'s cap on it.
    private static func standing(_ smaller: BodyID, on larger: BodyID, model: BRepModel,
                                 tolerance: ModelingTolerance) throws -> (face: FaceID, cap: FaceID, flush: Bool, circle: (center: Point3D, radius: Double))? {
        let operand: RevolvedSolidOperand
        do {
            operand = try RevolvedSolidOperand(bodyID: smaller, model: model, tolerance: tolerance)
        } catch let error as KernelError where error.code == .unsupportedCapability {
            return nil
        }
        let axis = operand.axis
        for (coordinate, other) in [(operand.lowerCoordinate, operand.upperCoordinate), (operand.upperCoordinate, operand.lowerCoordinate)] {
            let center = operand.center(at: coordinate)
            let radius = operand.radius(at: coordinate)
            // The face's outward normal points from the larger solid into the standing one.
            let outward = axis * (other > coordinate ? 1 : -1)
            guard let stoodOn = try face(of: larger, at: center, outward: outward, model: model, tolerance: tolerance),
                  try bounds(larger, plane: (center, outward), model: model, tolerance: tolerance),
                  let cap = try face(of: smaller, at: center, outward: outward * -1, model: model, tolerance: tolerance) else { continue }
            if try flushCap(larger, axis: axis, center: center, radius: radius, model: model, tolerance: tolerance) {
                return (stoodOn, cap, true, (center, radius))
            }
            // FIXME(INCOMPLETE_IMPLEMENTATION): a disc reaching the face's edges other than a
            // coaxial cap of its radius (a boss on a face's border) leaves walls meeting along a
            // shared boundary this plan does not join, so it takes no such pair, which the general
            // Boolean then refuses. Production path: Boolean union through
            // ExactBRepBooleanEvaluator.makePlan. Complete only when such contacts join, verified by
            // a boss standing across a plate's edge.
            guard try clears(stoodOn, disc: (center, radius), normal: outward, model: model, tolerance: tolerance) else { continue }
            return (stoodOn, cap, false, (center, radius))
        }
        return nil
    }

    /// Whether a body is a revolved solid coaxial with the standing one, of its radius at `center`.
    private static func flushCap(_ bodyID: BodyID, axis: Vector3D, center: Point3D, radius: Double, model: BRepModel,
                                 tolerance: ModelingTolerance) throws -> Bool {
        let operand: RevolvedSolidOperand
        do {
            operand = try RevolvedSolidOperand(bodyID: bodyID, model: model, tolerance: tolerance)
        } catch let error as KernelError where error.code == .unsupportedCapability {
            return false
        }
        guard abs(abs(operand.axis.dot(axis)) - 1) <= tolerance.angle else { return false }
        let coordinate = (center - .origin).dot(operand.axis)
        let offset = center - operand.center(at: coordinate)
        guard offset.length <= tolerance.distance else { return false }
        let ends = [operand.lowerCoordinate, operand.upperCoordinate]
        guard ends.contains(where: { abs($0 - coordinate) <= tolerance.distance }) else { return false }
        return abs(operand.radius(at: coordinate) - radius) <= tolerance.distance
    }

    /// The planar face of a body through `point` looking out along `outward`.
    private static func face(of bodyID: BodyID, at point: Point3D, outward: Vector3D, model: BRepModel,
                             tolerance: ModelingTolerance) throws -> FaceID? {
        for faceID in try faces(of: bodyID, model: model) {
            guard let face = model.faces[faceID], let surface = model.geometry.surfaces[face.surfaceID],
                  let plane = try DefaultPlanarSurfaceResolver().exactPlane(for: surface, tolerance: tolerance) else { continue }
            let normal = try plane.normal.normalized(tolerance: tolerance.distance) * (face.orientation == .forward ? 1 : -1)
            guard normal.dot(outward) >= 1 - tolerance.angle, abs((point - plane.origin).dot(normal)) <= tolerance.distance else { continue }
            return faceID
        }
        return nil
    }

    /// Whether the plane bounds the body: every vertex on its inner side, and every face a plane or
    /// a cylinder whose axis runs across it (whose points lie between its edges' along the normal).
    private static func bounds(_ bodyID: BodyID, plane: (origin: Point3D, normal: Vector3D), model: BRepModel,
                               tolerance: ModelingTolerance) throws -> Bool {
        let scope = try BodyTopologyScope(bodyID: bodyID, model: model)
        for reference in scope.references {
            switch reference {
            case let .vertex(vertexID):
                guard let point = model.vertices[vertexID]?.point else { throw TopologyError.missingReference("A vertex is missing.") }
                if (point - plane.origin).dot(plane.normal) > tolerance.distance { return false }
            case let .face(faceID):
                guard let face = model.faces[faceID], let surface = model.geometry.surfaces[face.surfaceID] else {
                    throw TopologyError.missingReference("A face is missing.")
                }
                if try DefaultPlanarSurfaceResolver().exactPlane(for: surface, tolerance: tolerance) != nil { continue }
                switch surface {
                case let .cylinder(cylinder):
                    if abs(abs(try cylinder.axis.normalized(tolerance: tolerance.distance).dot(plane.normal)) - 1) > tolerance.angle { return false }
                case let .analytic(.cylinder(_, axis, _)):
                    if abs(abs(try axis.normalized(tolerance: tolerance.distance).dot(plane.normal)) - 1) > tolerance.angle { return false }
                default:
                    return false
                }
            default:
                continue
            }
        }
        return true
    }

    /// Whether a disc in a planar face lies inside it clear of its edges: its centre inside the
    /// outline and outside every hole, and every straight or circular edge farther from the
    /// centre than the disc reaches.
    private static func clears(_ faceID: FaceID, disc: (center: Point3D, radius: Double), normal: Vector3D, model: BRepModel,
                               tolerance: ModelingTolerance) throws -> Bool {
        guard let face = model.faces[faceID] else { throw TopologyError.missingReference("A face is missing.") }
        let reach = disc.radius + tolerance.distance
        var crossings = 0
        // A ray from the centre across the face, its crossings with the boundary counted.
        let seed = abs(normal.x) < 0.9 ? Vector3D(x: 1, y: 0, z: 0) : Vector3D(x: 0, y: 1, z: 0)
        let ray = try (seed - normal * seed.dot(normal)).normalized(tolerance: tolerance.distance)
        let side = normal.cross(ray)
        for loopID in face.loops {
            guard let loop = model.loops[loopID] else { throw TopologyError.missingReference("A loop is missing.") }
            for coedge in loop.coedges {
                guard let edge = model.edges[coedge.edgeID], let curve = model.geometry.curves[edge.curveID],
                      let a = model.vertices[edge.startVertexID]?.point, let b = model.vertices[edge.endVertexID]?.point else {
                    throw TopologyError.missingReference("An edge is missing.")
                }
                switch curve {
                case .line:
                    let along = b - a
                    let t = max(0, min(1, (disc.center - a).dot(along) / along.dot(along)))
                    guard ((a + along * t) - disc.center).length > reach else { return false }
                    // The segment crosses the ray where it changes side across it ahead of the centre.
                    let (sa, sb) = ((a - disc.center).dot(side), (b - disc.center).dot(side))
                    if (sa > 0) != (sb > 0) {
                        let crossing = a + (b - a) * (sa / (sa - sb))
                        if (crossing - disc.center).dot(ray) > 0 { crossings += 1 }
                    }
                case let .circle(circle):
                    let offset = circle.center - disc.center
                    guard abs(offset.length - circle.radius) > reach else { return false }
                    // A circle round the centre (a whole loop, or its arcs together) encloses it once;
                    // sample the arc's crossings with the ray.
                    let samples = 64
                    let curve = Curve3D.circle(circle)
                    let t0 = try curve.parameterProjection(of: a, tolerance: tolerance).parameter
                    var t1 = try curve.parameterProjection(of: b, tolerance: tolerance).parameter
                    if let trim = edge.trim { t1 = t0 + (trim.endParameter - trim.startParameter) } else if t1 <= t0 { t1 += 2 * Double.pi }
                    var previous = try curve.point(at: t0, tolerance: tolerance)
                    for k in 1...samples {
                        let point = try curve.point(at: t0 + (t1 - t0) * Double(k) / Double(samples), tolerance: tolerance)
                        let (sa, sb) = ((previous - disc.center).dot(side), (point - disc.center).dot(side))
                        if (sa > 0) != (sb > 0) {
                            let crossing = previous + (point - previous) * (sa / (sa - sb))
                            if (crossing - disc.center).dot(ray) > 0 { crossings += 1 }
                        }
                        previous = point
                    }
                default:
                    return false
                }
            }
        }
        return crossings % 2 == 1
    }

    private static func faces(of bodyID: BodyID, model: BRepModel) throws -> [FaceID] {
        guard let body = model.bodies[bodyID] else { throw TopologyError.missingReference("A Boolean operand body is missing.") }
        return try body.shellIDs.flatMap { shellID -> [FaceID] in
            guard let shell = model.shells[shellID] else { throw TopologyError.missingReference("A Boolean operand shell is missing.") }
            return shell.faceIDs
        }
    }

    /// Both bodies' faces but the dropped cap, the face stood on holding the dropped cap's boundary
    /// as a hole (wound as the dropped cap's loop was: the two face each other, so it winds the
    /// other way about the face's outward normal, as a hole does).
    func request(featureID: FeatureID, model: BRepModel, subshapes: [SubshapeID: TopologyReference],
                 tolerance: ModelingTolerance) throws -> BRepSewingRequest {
        let builder = SourceBRepFacePatchBuilder()
        var patches: [BRepSewingFacePatch] = []
        var annulus: BRepSewingFacePatch?
        var dropped: BRepSewingFacePatch?
        for (prefix, bodyID) in [("standing-union:larger", largerBodyID), ("standing-union:smaller", smallerBodyID)] {
            for (index, faceID) in try Self.faces(of: bodyID, model: model).enumerated() {
                let patch = try builder.build(faceID: faceID, stableID: "\(prefix):face:\(index)", from: model,
                                              sourceSubshapes: subshapes, tolerance: tolerance).patch
                if faceID == annulusFaceID { annulus = patch } else if faceID == droppedFaceID { dropped = patch } else { patches.append(patch) }
            }
        }
        guard let annulus, let dropped, let boundary = dropped.loops.first(where: { $0.role == .outer }) else {
            throw KernelError(phase: .topology, code: .missingReference, tolerance: tolerance,
                              message: "A standing union's faces are missing.")
        }
        if flush {
            // Both caps go; each wall's rim on the shared circle is split where the other's is.
            let planeNormal = try annulus.surface.normal(u: 0, v: 0, tolerance: tolerance)
            func onCircle(_ edge: BRepSewingEdge) throws -> Bool {
                let middle = try edge.curve.point(at: 0.5 * (edge.startParameter + edge.endParameter), tolerance: tolerance)
                return [edge.startPoint, edge.endPoint, middle].allSatisfy { point in
                    let offset = point - circle.center
                    return abs(offset.length - circle.radius) <= tolerance.distance && abs(offset.dot(planeNormal)) <= tolerance.distance
                }
            }
            let corners = try patches.flatMap { patch in
                try patch.loops.flatMap { loop in try loop.edges.filter(onCircle).flatMap { [$0.startPoint, $0.endPoint] } }
            }
            let subdivider = BRepSewingEdgeSubdivider()
            patches = try patches.map { patch in
                BRepSewingFacePatch(stableID: patch.stableID, surface: patch.surface, orientation: patch.orientation,
                                    loops: try patch.loops.map { loop in
                                        BRepSewingLoop(stableID: loop.stableID, role: loop.role, edges: try loop.edges.flatMap { edge in
                                            try onCircle(edge) ? try subdivider.subdivide(edge, at: corners, tolerance: tolerance) : [edge]
                                        })
                                    }, parentSubshapeIDs: patch.parentSubshapeIDs)
            }
            return BRepSewingRequest(featureID: featureID, bodyKind: .solid,
                                     shells: [BRepSewingShell(stableID: "standing-union:shell", patches: patches)])
        }
        let pcurves = ExactFacePcurveBuilder()
        let hole = BRepSewingLoop(stableID: "\(annulus.stableID):hole", role: .inner, edges: try boundary.edges.map { edge in
            BRepSewingEdge(stableID: edge.stableID, curve: edge.curve, startParameter: edge.startParameter, endParameter: edge.endParameter,
                           startPoint: edge.startPoint, endPoint: edge.endPoint,
                           surfaceParameterCurve: try pcurves.surfaceParameterCurve(
                               for: edge.curve, startParameter: edge.startParameter, endParameter: edge.endParameter,
                               on: annulus.surface, tolerance: tolerance),
                           parentSubshapeIDs: edge.parentSubshapeIDs,
                           startVertexParentSubshapeIDs: edge.startVertexParentSubshapeIDs,
                           endVertexParentSubshapeIDs: edge.endVertexParentSubshapeIDs)
        })
        patches.append(BRepSewingFacePatch(stableID: annulus.stableID, surface: annulus.surface, orientation: annulus.orientation,
                                           loops: annulus.loops + [hole], parentSubshapeIDs: annulus.parentSubshapeIDs))
        return BRepSewingRequest(featureID: featureID, bodyKind: .solid,
                                 shells: [BRepSewingShell(stableID: "standing-union:shell", patches: patches)])
    }
}
