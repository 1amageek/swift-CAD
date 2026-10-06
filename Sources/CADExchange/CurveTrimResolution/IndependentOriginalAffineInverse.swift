import CADCore
import CADGeometry

/// Candidate inverse of an original nonsingular affine law under the caller's exact allowance.
struct IndependentOriginalAffineInverse {
    func point(_ point: Point3D, through frame: AffineTransform3D,
               usage: inout IndependentShapeExchangeUsage) throws -> Point3D {
        try frame.validate(); try point.validate()
        try usage.charge(entities: 16, work: 16, bytes: 15 * MemoryLayout<ExactRationalCoefficient>.stride)
        var x: [ExactRationalCoefficient] = [], y: [ExactRationalCoefficient] = [], z: [ExactRationalCoefficient] = []
        var displacement: [ExactRationalCoefficient] = []
        for value in [frame.basisX.x, frame.basisX.y, frame.basisX.z] { x.append(try .originalDouble(value, usage: &usage)) }
        for value in [frame.basisY.x, frame.basisY.y, frame.basisY.z] { y.append(try .originalDouble(value, usage: &usage)) }
        for value in [frame.basisZ.x, frame.basisZ.y, frame.basisZ.z] { z.append(try .originalDouble(value, usage: &usage)) }
        for (value, origin) in zip([point.x, point.y, point.z], [frame.translation.x, frame.translation.y, frame.translation.z]) {
            displacement.append(try ExactRationalCoefficient.originalDouble(value, usage: &usage)
                .subtracting(.originalDouble(origin, usage: &usage), usage: &usage))
        }
        let determinant = try triple(x, y, z, usage: &usage)
        guard !determinant.isZero else { throw IndependentShapeExchangeError.invalidAssociation("Original Cartesian trim image is exactly singular.") }
        let a = try triple(displacement, y, z, usage: &usage).divided(by: determinant, usage: &usage)
        let b = try triple(x, displacement, z, usage: &usage).divided(by: determinant, usage: &usage)
        let c = try triple(x, y, displacement, usage: &usage).divided(by: determinant, usage: &usage)
        let first = try a.outwardInterval(usage: &usage), second = try b.outwardInterval(usage: &usage), third = try c.outwardInterval(usage: &usage)
        let candidate = Point3D(x: first.lower * 0.5 + first.upper * 0.5,
            y: second.lower * 0.5 + second.upper * 0.5, z: third.lower * 0.5 + third.upper * 0.5)
        guard candidate.isFinite else { throw IndependentShapeExchangeError.invalidAssociation("Original affine trim inverse has no finite candidate.") }
        return candidate
    }

    private func triple(_ a: [ExactRationalCoefficient], _ b: [ExactRationalCoefficient],
                        _ c: [ExactRationalCoefficient], usage: inout IndependentShapeExchangeUsage) throws -> ExactRationalCoefficient {
        var result = ExactRationalCoefficient.zero
        for index in 0..<3 {
            let j = (index + 1) % 3, k = (index + 2) % 3
            let cross = try b[j].multiplied(by: c[k], usage: &usage)
                .subtracting(b[k].multiplied(by: c[j], usage: &usage), usage: &usage)
            result = try result.adding(a[index].multiplied(by: cross, usage: &usage), usage: &usage)
        }
        return result
    }
}
