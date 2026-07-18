import CADCore
import CADGeometry
import CADIR
import CADModeling

struct CapCoincidentCylinderOperands: Sendable {
    let polygon: [Point3D]
    let circle: Circle3D
    let axis: Vector3D
    let height: Double

    init(
        target: ConvexPlanarSolidOperand,
        tool: RevolvedSolidOperand,
        tolerance: ModelingTolerance
    ) throws {
        try tolerance.validate()
        guard case let .cylinder(_, radius) = tool.wall else {
            throw Self.unsupported(tolerance: tolerance)
        }
        let capCandidates = target.faces.compactMap {
            face -> (face: ConvexPlanarSolidFace, alignment: Double, coordinate: Double)? in
            let alignment = face.outwardNormal.dot(tool.axis)
            guard abs(abs(alignment) - 1.0) <= tolerance.angle else {
                return nil
            }
            return (
                face,
                alignment,
                Self.vector(face.planeOrigin).dot(tool.axis)
            )
        }
        guard capCandidates.count == 2,
              let lowerCap = capCandidates.first(where: { $0.alignment < 0.0 }),
              let upperCap = capCandidates.first(where: { $0.alignment > 0.0 }),
              abs(tool.lowerCoordinate - lowerCap.coordinate) <= tolerance.distance,
              abs(tool.upperCoordinate - upperCap.coordinate) <= tolerance.distance else {
            throw Self.unsupported(tolerance: tolerance)
        }
        let height = upperCap.coordinate - lowerCap.coordinate
        guard height > tolerance.distance else {
            throw Self.unsupported(tolerance: tolerance)
        }
        var polygon = lowerCap.face.vertices
        guard polygon.count >= 3 else {
            throw Self.unsupported(tolerance: tolerance)
        }
        if Self.signedArea(of: polygon, axis: tool.axis) < 0.0 {
            polygon.reverse()
        }

        self.polygon = polygon
        self.circle = Circle3D(
            center: tool.center(at: lowerCap.coordinate),
            normal: tool.axis,
            radius: radius
        )
        self.axis = tool.axis
        self.height = height
    }

    private static func signedArea(
        of polygon: [Point3D],
        axis: Vector3D
    ) -> Double {
        var areaVector = Vector3D.zero
        for index in polygon.indices {
            areaVector = areaVector
                + vector(polygon[index]).cross(
                    vector(polygon[(index + 1) % polygon.count])
                )
        }
        return areaVector.dot(axis) * 0.5
    }

    private static func vector(_ point: Point3D) -> Vector3D {
        Vector3D(x: point.x, y: point.y, z: point.z)
    }

    private static func unsupported(
        tolerance: ModelingTolerance
    ) -> KernelError {
        KernelError(
            phase: .topology,
            code: .unsupportedCapability,
            tolerance: tolerance,
            message: "Partial cylindrical Boolean requires equal target/tool axial bounds and an axis-parallel analytic cylinder."
        )
    }
}
