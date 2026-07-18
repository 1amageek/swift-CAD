import CADCore
import CADGeometry

enum ExactAnalyticFrame {
    static func directBasis(
        for normal: Vector3D,
        tolerance: ModelingTolerance
    ) throws -> (u: Vector3D, v: Vector3D) {
        let normalized = try normal.normalized(tolerance: tolerance.distance)
        let helper = abs(normalized.z) < 0.9 ? Vector3D.unitZ : Vector3D.unitY
        let u = try helper.cross(normalized).normalized(tolerance: tolerance.distance)
        return (u, normalized.cross(u))
    }

    static func analyticBasis(
        for normal: Vector3D,
        tolerance: ModelingTolerance
    ) throws -> (u: Vector3D, v: Vector3D) {
        let normalized = try normal.normalized(tolerance: tolerance.distance)
        let reference = abs(normalized.x) < 0.8 ? Vector3D.unitX : Vector3D.unitY
        let u = try normalized.cross(reference).normalized(tolerance: tolerance.distance)
        let v = try normalized.cross(u).normalized(tolerance: tolerance.distance)
        return (u, v)
    }
}
