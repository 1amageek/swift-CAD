import CADCore
import CADGeometry
import CADIR
import CADTopology

package struct ConvexPlanarSolidOperand: Sendable {
    package let bodyID: BodyID
    package let faces: [ConvexPlanarSolidFace]

    package init(
        bodyID: BodyID,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws {
        try tolerance.validate()
        guard let body = model.bodies[bodyID] else {
            throw TopologyError.missingReference("Convex planar Boolean operand body is missing.")
        }
        guard body.kind == .solid,
              body.shellIDs.count == 1,
              let shellID = body.shellIDs.first,
              let shell = model.shells[shellID],
              shell.faceIDs.count >= 4 else {
            throw Self.unsupported(tolerance, "Convex planar Boolean requires one closed solid shell with at least four faces.")
        }

        var extracted: [ConvexPlanarSolidFace] = []
        for faceID in shell.faceIDs.sorted() {
            guard let face = model.faces[faceID],
                  face.loops.count == 1,
                  let loopID = face.loops.first,
                  let loop = model.loops[loopID],
                  loop.role == .outer,
                  loop.coedges.count >= 3,
                  let surface = model.geometry.surfaces[face.surfaceID],
                  let plane = Self.plane(from: surface) else {
                throw Self.unsupported(tolerance, "Convex planar Boolean requires one straight outer loop on every planar face.")
            }
            for coedge in loop.coedges {
                guard let edge = model.edges[coedge.edgeID],
                      let curve = model.geometry.curves[edge.curveID],
                      Self.isLine(curve) else {
                    throw Self.unsupported(tolerance, "Convex planar Boolean requires exact line edges.")
                }
            }
            let vertices = try model.orderedPoints(for: loopID)
            try Self.validateConvexPolygon(
                vertices,
                planeNormal: plane.normal,
                tolerance: tolerance
            )
            let reverseNormal = (shell.orientation == .reversed) != (face.orientation == .reversed)
            extracted.append(ConvexPlanarSolidFace(
                faceID: faceID,
                surface: surface,
                orientation: reverseNormal ? .reversed : .forward,
                planeOrigin: plane.origin,
                outwardNormal: reverseNormal ? -plane.normal : plane.normal,
                vertices: vertices
            ))
        }

        let allVertices = extracted.flatMap(\.vertices)
        for face in extracted {
            for vertex in allVertices {
                let signedDistance = (vertex - face.planeOrigin).dot(face.outwardNormal)
                guard signedDistance <= tolerance.distance else {
                    throw Self.unsupported(
                        tolerance,
                        "Convex planar Boolean operand is concave or has inconsistent face orientation."
                    )
                }
            }
        }
        self.bodyID = bodyID
        self.faces = extracted
    }

    private static func plane(
        from surface: Surface3D
    ) -> (origin: Point3D, normal: Vector3D)? {
        switch surface {
        case let .plane(plane):
            return (plane.origin, plane.normal)
        case let .analytic(.plane(origin, normal)):
            return (origin, normal)
        case .cylinder, .analytic, .bSpline:
            return nil
        }
    }

    private static func isLine(_ curve: Curve3D) -> Bool {
        switch curve {
        case .line, .analytic(.line):
            return true
        case .circle,
             .analytic,
             .bSpline,
             .implicit,
             .surfaceLift,
             .certifiedIntersection:
            return false
        }
    }

    private static func validateConvexPolygon(
        _ vertices: [Point3D],
        planeNormal: Vector3D,
        tolerance: ModelingTolerance
    ) throws {
        guard vertices.count >= 3 else {
            throw unsupported(tolerance, "Convex planar Boolean face has fewer than three vertices.")
        }
        var windingSign = 0.0
        for index in vertices.indices {
            let previous = vertices[(index + vertices.count - 1) % vertices.count]
            let current = vertices[index]
            let next = vertices[(index + 1) % vertices.count]
            let first = current - previous
            let second = next - current
            guard first.length > tolerance.distance,
                  second.length > tolerance.distance else {
                throw unsupported(tolerance, "Convex planar Boolean face contains a collapsed edge.")
            }
            let signedTurn = first.cross(second).dot(planeNormal)
            let threshold = tolerance.distance * (first.length + second.length)
            if abs(signedTurn) <= threshold {
                continue
            }
            if windingSign == 0.0 {
                windingSign = signedTurn
            } else if windingSign * signedTurn < 0.0 {
                throw unsupported(tolerance, "Convex planar Boolean does not accept concave face loops.")
            }
        }
        guard windingSign != 0.0 else {
            throw unsupported(tolerance, "Convex planar Boolean face has zero area.")
        }
    }

    private static func unsupported(
        _ tolerance: ModelingTolerance,
        _ message: String
    ) -> KernelError {
        KernelError(
            phase: .validation,
            code: .unsupportedCapability,
            tolerance: tolerance,
            message: message
        )
    }
}
