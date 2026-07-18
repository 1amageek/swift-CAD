import CADCore
import CADGeometry

struct PlanarFaceFrame: Sendable {
    let origin: Point3D
    let u: Vector3D
    let v: Vector3D

    init(plane: Plane3D, tolerance: ModelingTolerance) throws {
        let normal = try plane.normal.normalized(tolerance: tolerance.distance)
        let helper = abs(normal.z) < 0.9 ? Vector3D.unitZ : Vector3D.unitY
        u = try helper.cross(normal).normalized(tolerance: tolerance.distance)
        v = normal.cross(u)
        origin = plane.origin
    }

    func localPoint(_ point: Point3D) -> Point2D {
        let delta = point - origin
        return Point2D(x: delta.dot(u), y: delta.dot(v))
    }

    func worldPoint(_ point: Point2D) -> Point3D {
        origin + (u * point.x) + (v * point.y)
    }
}
