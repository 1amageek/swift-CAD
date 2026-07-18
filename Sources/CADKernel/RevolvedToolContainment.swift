import CADCore
import CADGeometry
import CADModeling

struct RevolvedToolContainment: Sendable {
    let containsTarget: Bool

    init(
        target: ConvexPlanarSolidOperand,
        tool: RevolvedSolidOperand,
        tolerance: ModelingTolerance
    ) throws {
        try tolerance.validate()
        let vertices = Array(Set(target.faces.flatMap(\.vertices)))
        guard vertices.isEmpty == false else {
            containsTarget = false
            return
        }
        containsTarget = vertices.allSatisfy { point in
            let coordinate = Self.vector(point).dot(tool.axis)
            guard coordinate >= tool.lowerCoordinate - tolerance.distance,
                  coordinate <= tool.upperCoordinate + tolerance.distance else {
                return false
            }
            let center = tool.center(at: coordinate)
            let offset = point - center
            let radial = offset - tool.axis * offset.dot(tool.axis)
            return radial.length <= tool.radius(at: coordinate) + tolerance.distance
        }
    }

    private static func vector(_ point: Point3D) -> Vector3D {
        Vector3D(x: point.x, y: point.y, z: point.z)
    }
}
