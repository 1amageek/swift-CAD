import CADCore

public enum RobustPredicates {
    public static func orientation2D(_ a: Point2D, _ b: Point2D, relativeTo c: Point2D,
        determinantTolerance: Double) throws -> RobustSign {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try orientation2D(a, b, relativeTo: c,
            determinantTolerance: determinantTolerance, using: &execution)
    }

    /// Adaptive original sign with caller-owned arithmetic and allocation admission.
    public static func orientation2D<A: ExactScalarAdmission & ~Copyable>(_ a: Point2D, _ b: Point2D, relativeTo c: Point2D,
        determinantTolerance: Double, using execution: inout A) throws -> RobustSign {
        try execution.consumeWork(1)
        guard determinantTolerance.isFinite, determinantTolerance >= 0,
            a.x.isFinite, a.y.isFinite, b.x.isFinite, b.y.isFinite,
            c.x.isFinite, c.y.isFinite else {
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
        let uncertaintyBound = (determinantTolerance + roundoffBound).nextUp
        if normalProduct(acX, bcY, left), normalProduct(acY, bcX, right),
            roundoffBound.isNormal, determinant.isFinite, abs(determinant) > uncertaintyBound {
            try execution.checkpoint()
            return determinant < 0.0 ? .negative : .positive
        }

        let ax = try ExactRationalCoefficient.originalDouble(a.x, usage: &execution)
            .subtracting(.originalDouble(c.x, usage: &execution), usage: &execution)
        let ay = try ExactRationalCoefficient.originalDouble(a.y, usage: &execution)
            .subtracting(.originalDouble(c.y, usage: &execution), usage: &execution)
        let bx = try ExactRationalCoefficient.originalDouble(b.x, usage: &execution)
            .subtracting(.originalDouble(c.x, usage: &execution), usage: &execution)
        let by = try ExactRationalCoefficient.originalDouble(b.y, usage: &execution)
            .subtracting(.originalDouble(c.y, usage: &execution), usage: &execution)
        let exactDeterminant = try ax.multiplied(by: by, usage: &execution)
            .subtracting(ay.multiplied(by: bx, usage: &execution), usage: &execution)
        if exactDeterminant.isZero { try execution.checkpoint(); return .zero }
        let magnitude = exactDeterminant.isNegative ? exactDeterminant.negated : exactDeterminant
        let threshold = try ExactRationalCoefficient.originalDouble(determinantTolerance, usage: &execution)
        guard try magnitude.subtracting(threshold, usage: &execution).isPositive else { try execution.checkpoint(); return .indeterminate }
        try execution.checkpoint()
        return exactDeterminant.isNegative ? .negative : .positive
    }

    public static func orientation3D(_ a: Point3D, _ b: Point3D, _ c: Point3D,
        relativeTo d: Point3D, determinantTolerance: Double) throws -> RobustSign {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try orientation3D(a, b, c, relativeTo: d,
            determinantTolerance: determinantTolerance, using: &execution)
    }

    public static func orientation3D<A: ExactScalarAdmission & ~Copyable>(
        _ a: Point3D,
        _ b: Point3D,
        _ c: Point3D,
        relativeTo d: Point3D,
        determinantTolerance: Double, using execution: inout A
    ) throws -> RobustSign {
        try execution.checkpoint()
        try execution.consumeWork(1)
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
        let yz = ac.y * ad.z, zy = ac.z * ad.y
        let zx = ac.z * ad.x, xz = ac.x * ad.z
        let xy = ac.x * ad.y, yx = ac.y * ad.x
        let cross = Vector3D(x: yz - zy, y: zx - xz, z: xy - yx)
        let determinant = ab.dot(cross)
        let permanent = abs(ab.x) * (abs(yz) + abs(zy))
            + abs(ab.y) * (abs(zx) + abs(xz))
            + abs(ab.z) * (abs(xy) + abs(yx))
        let roundoffBound = permanent * Double.ulpOfOne * 16.0
        let uncertaintyBound = (determinantTolerance + roundoffBound).nextUp
        // Normal products and a normal bound keep the filter's relative-error proof valid.
        let productsAreNormal = normalProduct(ac.y, ad.z, yz) && normalProduct(ac.z, ad.y, zy)
            && normalProduct(ac.z, ad.x, zx) && normalProduct(ac.x, ad.z, xz)
            && normalProduct(ac.x, ad.y, xy) && normalProduct(ac.y, ad.x, yx)
        if productsAreNormal, roundoffBound.isNormal,
            determinant.isFinite, abs(determinant) > uncertaintyBound {
            try execution.checkpoint()
            return determinant < 0.0 ? .negative : .positive
        }

        let exactDeterminant = try exactOrientationDeterminant(a, b, c, relativeTo: d, using: &execution)
        if exactDeterminant.isZero { try execution.checkpoint(); return .zero }
        let magnitude = exactDeterminant.isNegative ? exactDeterminant.negated : exactDeterminant
        let threshold = try ExactRationalCoefficient.originalDouble(determinantTolerance, usage: &execution)
        guard try magnitude.subtracting(threshold, usage: &execution).isPositive else {
            try execution.checkpoint(); return .indeterminate
        }
        try execution.checkpoint()
        return exactDeterminant.isNegative ? .negative : .positive
    }

    private static func normalProduct(_ lhs: Double, _ rhs: Double, _ result: Double) -> Bool {
        lhs.isFinite && rhs.isFinite && (lhs == 0 || rhs == 0 || result.isNormal)
    }

    private static func exactOrientationDeterminant<A: ExactScalarAdmission & ~Copyable>(
        _ a: Point3D, _ b: Point3D, _ c: Point3D,
        relativeTo d: Point3D, using execution: inout A
    ) throws -> ExactRationalCoefficient {
        let dx = try ExactRationalCoefficient.originalDouble(d.x, usage: &execution)
        let dy = try ExactRationalCoefficient.originalDouble(d.y, usage: &execution)
        let dz = try ExactRationalCoefficient.originalDouble(d.z, usage: &execution)
        let ax = try ExactRationalCoefficient.originalDouble(a.x, usage: &execution).subtracting(dx, usage: &execution)
        let ay = try ExactRationalCoefficient.originalDouble(a.y, usage: &execution).subtracting(dy, usage: &execution)
        let az = try ExactRationalCoefficient.originalDouble(a.z, usage: &execution).subtracting(dz, usage: &execution)
        let bx = try ExactRationalCoefficient.originalDouble(b.x, usage: &execution).subtracting(dx, usage: &execution)
        let by = try ExactRationalCoefficient.originalDouble(b.y, usage: &execution).subtracting(dy, usage: &execution)
        let bz = try ExactRationalCoefficient.originalDouble(b.z, usage: &execution).subtracting(dz, usage: &execution)
        let cx = try ExactRationalCoefficient.originalDouble(c.x, usage: &execution).subtracting(dx, usage: &execution)
        let cy = try ExactRationalCoefficient.originalDouble(c.y, usage: &execution).subtracting(dy, usage: &execution)
        let cz = try ExactRationalCoefficient.originalDouble(c.z, usage: &execution).subtracting(dz, usage: &execution)
        let crossX = try by.multiplied(by: cz, usage: &execution)
            .subtracting(bz.multiplied(by: cy, usage: &execution), usage: &execution)
        let crossY = try bz.multiplied(by: cx, usage: &execution)
            .subtracting(bx.multiplied(by: cz, usage: &execution), usage: &execution)
        let crossZ = try bx.multiplied(by: cy, usage: &execution)
            .subtracting(by.multiplied(by: cx, usage: &execution), usage: &execution)
        return try ax.multiplied(by: crossX, usage: &execution)
            .adding(ay.multiplied(by: crossY, usage: &execution), usage: &execution)
            .adding(az.multiplied(by: crossZ, usage: &execution), usage: &execution)
    }
}
