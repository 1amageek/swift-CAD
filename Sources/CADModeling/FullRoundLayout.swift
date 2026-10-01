import Foundation
import CADCore
import CADGeometry
import CADTopology

/// Fillet Shell's Full shape across a prismatic center face: the two selected straight edges bound
/// the center face, and their other faces (left and right) are planes along the same direction. The
/// round is the circle tangent to the three faces' lines across that direction: its centre where
/// the two corners' bisectors meet, its radius `width / (cot(α₁/2) + cot(α₂/2))` for the corners'
/// interior angles α, touching the left and right faces `radius·cot(α/2)` from their corners and the
/// center face where those distances meet.
package struct FullRoundLayout {
    package let centerFaceID: FaceID
    package let leftFaceID: FaceID
    package let rightFaceID: FaceID
    /// The first edge's ends, and the second edge's ends opposite them.
    package let firstEnds: (Point3D, Point3D)
    package let secondEnds: (Point3D, Point3D)
    /// The unit direction both edges run along, from the first ends to the second.
    package let axis: Vector3D
    /// Unit directions across the axis: along the center face from the first edge to the second,
    /// and into the left and right faces away from their corners.
    package let acrossCenter: Vector3D
    package let intoLeft: Vector3D
    package let intoRight: Vector3D
    package let radius: Double
    /// How far the round touches the left and right faces from their corners (and the center face
    /// from each corner).
    package let leftSetback: Double
    package let rightSetback: Double
    /// The quarter-arc weights at the two corners: the sines of half their interior angles.
    package let leftWeight: Double
    package let rightWeight: Double

    package init(model: BRepModel, bodyID: BodyID, firstEdgeID: EdgeID, secondEdgeID: EdgeID,
                 featureID: FeatureID?, tolerance: ModelingTolerance) throws {
        func failure(_ code: KernelErrorCode, _ message: String) -> KernelError {
            KernelError(phase: .evaluation, code: code, featureID: featureID, tolerance: tolerance, message: message)
        }
        guard let body = model.bodies[bodyID], body.kind == .solid, body.shellIDs.count == 1,
              let shell = model.shells[body.shellIDs[0]] else {
            throw failure(.unsupportedCapability, "A full fillet rounds one single-shell solid body.")
        }
        func faces(of edgeID: EdgeID) throws -> [FaceID] {
            try shell.faceIDs.filter { faceID in
                guard let face = model.faces[faceID] else { throw TopologyError.missingReference("Missing face.") }
                return try face.loops.contains { loopID in
                    guard let loop = model.loops[loopID] else { throw TopologyError.missingReference("Missing loop.") }
                    return loop.edges.contains { $0.edgeID == edgeID }
                }
            }
        }
        let (firstFaces, secondFaces) = (try faces(of: firstEdgeID), try faces(of: secondEdgeID))
        let shared = firstFaces.filter { secondFaces.contains($0) }
        guard firstFaces.count == 2, secondFaces.count == 2, shared.count == 1,
              let leftID = firstFaces.first(where: { $0 != shared[0] }),
              let rightID = secondFaces.first(where: { $0 != shared[0] }) else {
            throw failure(.invalidInput, "A full fillet's two edges bound one face between two others.")
        }
        /// A face's plane normal, outward from the solid.
        func outward(_ faceID: FaceID) throws -> Vector3D {
            guard let face = model.faces[faceID], case let .plane(plane) = model.geometry.surfaces[face.surfaceID] else {
                // FIXME(INCOMPLETE_IMPLEMENTATION): a full round beside curved faces other than a
                // tube end's coaxial walls (FullRimRoundBuilder) needs the circle tangent to curves
                // across the edges, which is not built, so it is refused. Production path:
                // FullRoundLayout for every other Full fillet. Complete only when such neighbours
                // are rounded, verified by a full round across a face between a plane and a
                // cylinder running along it.
                throw failure(.unsupportedCapability, "A full fillet rounds across planar faces.")
            }
            return try (face.orientation == .forward ? plane.normal : plane.normal * -1).normalized(tolerance: tolerance.distance)
        }
        let (center, left, right) = (try outward(shared[0]), try outward(leftID), try outward(rightID))
        func ends(_ edgeID: EdgeID) throws -> (Point3D, Point3D) {
            guard let edge = model.edges[edgeID], case .line = model.geometry.curves[edge.curveID],
                  let start = model.vertices[edge.startVertexID]?.point, let end = model.vertices[edge.endVertexID]?.point else {
                throw failure(.unsupportedCapability, "A full fillet's edges are straight.")
            }
            return (start, end)
        }
        let (a1, b1) = try ends(firstEdgeID)
        var (a2, b2) = try ends(secondEdgeID)
        let axis = try (b1 - a1).normalized(tolerance: tolerance.distance)
        if (a2 - a1).dot(axis) > (b2 - a1).dot(axis) { swap(&a2, &b2) }
        let offset = a2 - a1
        let across = offset - axis * offset.dot(axis)
        let width = across.length
        guard width > tolerance.distance, (b2 - a2 - (b1 - a1)).length <= tolerance.distance,
              [center, left, right].allSatisfy({ abs($0.dot(axis)) <= tolerance.angle }),
              abs(offset.dot(axis)) <= tolerance.distance else {
            throw failure(.unsupportedCapability,
                          "A full fillet's edges run side by side along one direction across a center face, its neighbours along it too.")
        }
        let acrossCenter = across * (1 / width)
        /// The direction into a side face from its corner: across the axis, within the face, away
        /// from the center face's outside.
        func into(_ normal: Vector3D) throws -> Vector3D {
            var direction = try axis.cross(normal).normalized(tolerance: tolerance.distance)
            if direction.dot(center) > 0 { direction = direction * -1 }
            return direction
        }
        let (intoLeft, intoRight) = (try into(left), try into(right))
        // Interior angles at the corners, between the center face and each side face.
        let alpha1 = acos(max(-1, min(1, acrossCenter.dot(intoLeft))))
        let alpha2 = acos(max(-1, min(1, (acrossCenter * -1).dot(intoRight))))
        guard left.dot(acrossCenter) < -tolerance.angle, right.dot(acrossCenter) > tolerance.angle,
              alpha1 > tolerance.angle, alpha2 > tolerance.angle else {
            throw failure(.unsupportedCapability, "A full fillet rounds across a face whose two edges are convex.")
        }
        let (cot1, cot2) = (1 / tan(alpha1 / 2), 1 / tan(alpha2 / 2))
        let radius = width / (cot1 + cot2)
        centerFaceID = shared[0]
        leftFaceID = leftID
        rightFaceID = rightID
        firstEnds = (a1, b1)
        secondEnds = (a2, b2)
        self.axis = axis
        self.acrossCenter = acrossCenter
        self.intoLeft = intoLeft
        self.intoRight = intoRight
        self.radius = radius
        leftSetback = radius * cot1
        rightSetback = radius * cot2
        leftWeight = sin(alpha1 / 2)
        rightWeight = sin(alpha2 / 2)
    }

    /// The round's cross-section through `first` (a point of the first edge) and `second` (the
    /// second edge's point across from it): from the left face's contact over the center to the
    /// right face's, two circular arcs meeting where the round touches the center face.
    package func section(first: Point3D, second: Point3D) -> (points: [Point3D], weights: [Double]) {
        ([first + intoLeft * leftSetback, first, first + acrossCenter * leftSetback, second, second + intoRight * rightSetback],
         [1, leftWeight, 1, rightWeight, 1])
    }
}
