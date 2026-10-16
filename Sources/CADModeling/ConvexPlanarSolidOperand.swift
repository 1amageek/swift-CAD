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
        var execution = try OriginalQueryExecution.independentGeometry()
        try self.init(bodyID: bodyID, model: model, tolerance: tolerance, using: &execution)
    }

    package init(
        bodyID: BodyID,
        model: BRepModel,
        tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution
    ) throws {
        try execution.consumeWork(1)
        try tolerance.validate()
        guard let body = model.bodies[bodyID] else {
            throw TopologyError.missingReference("Convex planar Boolean operand body is missing.")
        }
        let shellIDs = try body.originalShellIDs(using: &execution)
        guard body.kind == .solid,
              shellIDs.count == 1,
              let shellID = shellIDs.first,
              let shell = model.shells[shellID],
              shell.faceIDs.count >= 4 else {
            throw Self.unsupported(tolerance, "Convex planar Boolean requires one closed solid shell with at least four faces.")
        }

        try execution.retainStorage(count: shell.faceIDs.count,
            stride: MemoryLayout<FaceID>.stride + MemoryLayout<ConvexPlanarSolidFace>.stride)
        let orderedFaceIDs = try shell.faceIDs.sorted {
            try execution.consumeWork(1)
            return $0 < $1
        }
        var extracted: [ConvexPlanarSolidFace] = []
        for faceID in orderedFaceIDs {
            try execution.consumeWork(1)
            guard let face = model.faces[faceID],
                  face.loops.count == 1,
                  let loopID = face.loops.first,
                  let loop = model.loops[loopID],
                  loop.role == .outer,
                  loop.coedges.count >= 3,
                  let surface = model.geometry.surfaces[face.surfaceID],
                  let plane = try Self.plane(
                      from: surface,
                      tolerance: tolerance, using: &execution
                  ) else {
                throw Self.unsupported(tolerance, "Convex planar Boolean requires one straight outer loop on every planar face.")
            }
            for coedge in loop.coedges {
                try execution.consumeWork(1)
                guard let edge = model.edges[coedge.edgeID],
                      let curve = model.geometry.curves[edge.curveID],
                      try Self.isLine(curve, using: &execution) else {
                    throw Self.unsupported(tolerance, "Convex planar Boolean requires exact line edges.")
                }
            }
            let vertices = try model.orderedPoints(for: loopID, using: &execution)
            try Self.validateConvexPolygon(
                vertices,
                planeNormal: plane.normal,
                tolerance: tolerance, using: &execution
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

        var vertexCount = 0
        for face in extracted {
            try execution.consumeWork(1)
            let total = vertexCount.addingReportingOverflow(face.vertices.count)
            guard !total.overflow else { throw ExactScalarFailure.countOverflow }
            vertexCount = total.partialValue
        }
        try execution.retainStorage(count: vertexCount, stride: MemoryLayout<Point3D>.stride)
        var allVertices: [Point3D] = []
        allVertices.reserveCapacity(vertexCount)
        for face in extracted {
            for vertex in face.vertices {
                try execution.consumeWork(1)
                allVertices.append(vertex)
            }
        }
        for face in extracted {
            for vertex in allVertices {
                try execution.consumeWork(1)
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
        from surface: Surface3D,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> (origin: Point3D, normal: Vector3D)? {
        guard let plane = try DefaultPlanarSurfaceResolver().exactPlane(
            for: surface,
            tolerance: tolerance, using: &execution
        ) else { return nil }
        return (plane.origin, plane.normal)
    }

    private static func isLine(_ curve: Curve3D,
        using execution: inout OriginalQueryExecution) throws -> Bool {
        try curve.exactLinearLocus(using: &execution) != nil
    }

    private static func validateConvexPolygon(
        _ vertices: [Point3D],
        planeNormal: Vector3D,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws {
        guard vertices.count >= 3 else {
            throw unsupported(tolerance, "Convex planar Boolean face has fewer than three vertices.")
        }
        var windingSign = 0.0
        for index in vertices.indices {
            try execution.consumeWork(1)
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
