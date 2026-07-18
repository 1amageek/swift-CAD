import CADCore

public enum RobustPredicates {
    public static func orientation2D(
        _ a: Point2D,
        _ b: Point2D,
        relativeTo c: Point2D,
        determinantTolerance: Double
    ) throws -> RobustSign {
        guard determinantTolerance.isFinite,
              determinantTolerance >= 0.0,
              a.x.isFinite,
              a.y.isFinite,
              b.x.isFinite,
              b.y.isFinite,
              c.x.isFinite,
              c.y.isFinite else {
            throw GeometryError.invalidDistance(determinantTolerance)
        }

        let acX = a.x - c.x
        let acY = a.y - c.y
        let bcX = b.x - c.x
        let bcY = b.y - c.y
        let left = acX * bcY
        let right = acY * bcX
        let determinant = left - right
        let roundoffBound = (abs(left) + abs(right)) * Double.ulpOfOne * 8.0
        let uncertaintyBound = max(determinantTolerance, roundoffBound)
        if determinant.isFinite, abs(determinant) > uncertaintyBound {
            return determinant < 0.0 ? .negative : .positive
        }

        let exactDeterminant = FloatingPointExpansion.subtract(
            FloatingPointExpansion.product(
                FloatingPointExpansion.difference(a.x, c.x),
                FloatingPointExpansion.difference(b.y, c.y)
            ),
            FloatingPointExpansion.product(
                FloatingPointExpansion.difference(a.y, c.y),
                FloatingPointExpansion.difference(b.x, c.x)
            )
        )
        let exactSign = FloatingPointExpansion.sign(exactDeterminant)
        guard exactSign != .zero else { return .zero }
        let exactEstimate = FloatingPointExpansion.estimate(exactDeterminant)
        guard exactEstimate.isFinite,
              abs(exactEstimate) > determinantTolerance else {
            return .indeterminate
        }
        return exactSign
    }

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

        if determinant.isFinite, abs(determinant) > uncertaintyBound {
            return determinant < 0.0 ? .negative : .positive
        }

        let exactDeterminant = exactOrientationDeterminant(a, b, c, relativeTo: d)
        let exactSign = FloatingPointExpansion.sign(exactDeterminant)
        guard exactSign != .zero else {
            return .zero
        }
        let exactEstimate = FloatingPointExpansion.estimate(exactDeterminant)
        guard exactEstimate.isFinite,
              abs(exactEstimate) > determinantTolerance else {
            return .indeterminate
        }
        return exactSign
    }

    private static func exactOrientationDeterminant(
        _ a: Point3D,
        _ b: Point3D,
        _ c: Point3D,
        relativeTo d: Point3D
    ) -> [Double] {
        let ax = FloatingPointExpansion.difference(a.x, d.x)
        let ay = FloatingPointExpansion.difference(a.y, d.y)
        let az = FloatingPointExpansion.difference(a.z, d.z)
        let bx = FloatingPointExpansion.difference(b.x, d.x)
        let by = FloatingPointExpansion.difference(b.y, d.y)
        let bz = FloatingPointExpansion.difference(b.z, d.z)
        let cx = FloatingPointExpansion.difference(c.x, d.x)
        let cy = FloatingPointExpansion.difference(c.y, d.y)
        let cz = FloatingPointExpansion.difference(c.z, d.z)

        let crossX = FloatingPointExpansion.subtract(
            FloatingPointExpansion.product(by, cz),
            FloatingPointExpansion.product(bz, cy)
        )
        let crossY = FloatingPointExpansion.subtract(
            FloatingPointExpansion.product(bz, cx),
            FloatingPointExpansion.product(bx, cz)
        )
        let crossZ = FloatingPointExpansion.subtract(
            FloatingPointExpansion.product(bx, cy),
            FloatingPointExpansion.product(by, cx)
        )
        return FloatingPointExpansion.sum(
            FloatingPointExpansion.sum(
                FloatingPointExpansion.product(ax, crossX),
                FloatingPointExpansion.product(ay, crossY)
            ),
            FloatingPointExpansion.product(az, crossZ)
        )
    }
}
