import CADCore

public enum RobustPredicates {
    public static func orientation3D(
        _ a: Point3D,
        _ b: Point3D,
        _ c: Point3D,
        relativeTo d: Point3D,
        determinantTolerance: Double
    ) throws -> RobustSign {
        guard determinantTolerance.isFinite, determinantTolerance >= 0.0 else {
            throw GeometryError.invalidDistance(determinantTolerance)
        }
        try a.validate()
        try b.validate()
        try c.validate()
        try d.validate()

        let ab = a - d
        let ac = b - d
        let ad = c - d
        let cross = ac.cross(ad)
        let determinant = ab.dot(cross)
        let permanent = abs(ab.x * cross.x) + abs(ab.y * cross.y) + abs(ab.z * cross.z)
        let roundoffBound = permanent * Double.ulpOfOne * 16.0
        let uncertaintyBound = max(determinantTolerance, roundoffBound)

        if determinant == 0.0 {
            return .zero
        }
        if abs(determinant) <= uncertaintyBound {
            return .indeterminate
        }
        return determinant < 0.0 ? .negative : .positive
    }
}
