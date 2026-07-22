import CADCore
import CADGeometry
import CADTopology

public extension SubshapeGeometrySignature {
    static func lineEdge(
        startPoint: Point3D,
        endPoint: Point3D
    ) throws -> SubshapeGeometrySignature {
        let delta = endPoint - startPoint
        let length = delta.length
        let direction = try delta.normalized(tolerance: Double.leastNonzeroMagnitude)
        return .edge(CurveSpanGeometrySignature(
            curve: .line(Line3D(
                origin: startPoint,
                direction: direction
            )),
            startParameter: 0.0,
            endParameter: length,
            startPoint: startPoint,
            endPoint: endPoint
        ))
    }

    static func untrimmedFace(
        surface: Surface3D,
        orientation: Orientation = .forward
    ) -> SubshapeGeometrySignature {
        .face(FaceGeometrySignature(
            surface: surface,
            orientation: orientation,
            loops: []
        ))
    }

    static func untrimmedPlane(
        origin: Point3D,
        normal: Vector3D = .unitZ,
        orientation: Orientation = .forward
    ) -> SubshapeGeometrySignature {
        .untrimmedFace(
            surface: .analytic(.plane(origin: origin, normal: normal)),
            orientation: orientation
        )
    }
}
