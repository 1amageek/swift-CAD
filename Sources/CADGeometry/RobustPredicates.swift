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

    /// Exact original sign with caller-owned work and optional byte admission.
    package static func orientation2D(_ a: Point2D, _ b: Point2D, relativeTo c: Point2D,
        determinantTolerance: Double, consumeWork: () throws -> Void,
        consumeStorage: ((Int) throws -> Void)? = nil) throws -> RobustSign {
        try consumeWork()
        guard determinantTolerance.isFinite, determinantTolerance >= 0,
            a.x.isFinite, a.y.isFinite, b.x.isFinite, b.y.isFinite,
            c.x.isFinite, c.y.isFinite else {
            throw GeometryError.invalidDistance(determinantTolerance)
        }
        return try withoutActuallyEscaping(consumeWork) { work in
            var usage = OriginalGeometryValidationAdmission(consumeWork: { _ in try work() },
                consumeStorage: consumeStorage)
            let ax = try ExactRationalCoefficient.originalDouble(a.x, usage: &usage)
                .subtracting(.originalDouble(c.x, usage: &usage), usage: &usage)
            let ay = try ExactRationalCoefficient.originalDouble(a.y, usage: &usage)
                .subtracting(.originalDouble(c.y, usage: &usage), usage: &usage)
            let bx = try ExactRationalCoefficient.originalDouble(b.x, usage: &usage)
                .subtracting(.originalDouble(c.x, usage: &usage), usage: &usage)
            let by = try ExactRationalCoefficient.originalDouble(b.y, usage: &usage)
                .subtracting(.originalDouble(c.y, usage: &usage), usage: &usage)
            let determinant = try ax.multiplied(by: by, usage: &usage)
                .subtracting(ay.multiplied(by: bx, usage: &usage), usage: &usage)
            if determinant.isZero { return .zero }
            let magnitude = determinant.isNegative ? determinant.negated : determinant
            let threshold = try ExactRationalCoefficient.originalDouble(determinantTolerance, usage: &usage)
            guard try magnitude.subtracting(threshold, usage: &usage).isPositive else { return .indeterminate }
            return determinant.isNegative ? .negative : .positive
        }
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
