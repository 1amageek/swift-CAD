import CADCore
import CADGeometry

/// Candidate inverse of an original nonsingular affine law under the caller's exact allowance.
struct IndependentOriginalAffineInverse {
    func point(_ point: Point3D, through frame: AffineTransform3D,
               usage: IndependentShapeExchangeOwner, using execution: inout OriginalQueryExecution) throws -> Point3D {
        try frame.validate(); try point.validate()
        try execution.consumeWork(1)
        try execution.retainStorage(count: 12, stride: MemoryLayout<ExactRationalCoefficient>.stride)
        var x: [ExactRationalCoefficient] = [], y: [ExactRationalCoefficient] = [], z: [ExactRationalCoefficient] = []
        var displacement: [ExactRationalCoefficient] = []
        x.reserveCapacity(3); y.reserveCapacity(3); z.reserveCapacity(3); displacement.reserveCapacity(3)
        for value in [frame.basisX.x, frame.basisX.y, frame.basisX.z] { try execution.consumeWork(1); x.append(try .originalDouble(value, usage: &execution)) }
        for value in [frame.basisY.x, frame.basisY.y, frame.basisY.z] { try execution.consumeWork(1); y.append(try .originalDouble(value, usage: &execution)) }
        for value in [frame.basisZ.x, frame.basisZ.y, frame.basisZ.z] { try execution.consumeWork(1); z.append(try .originalDouble(value, usage: &execution)) }
        for (value, origin) in zip([point.x, point.y, point.z], [frame.translation.x, frame.translation.y, frame.translation.z]) {
            try execution.consumeWork(1)
            displacement.append(try ExactRationalCoefficient.originalDouble(value, usage: &execution)
                .subtracting(.originalDouble(origin, usage: &execution), usage: &execution))
        }
        let determinant = try triple(x, y, z, using: &execution)
        guard !determinant.isZero else { throw IndependentShapeExchangeError.invalidAssociation("Original Cartesian trim image is exactly singular.") }
        let a = try triple(displacement, y, z, using: &execution).divided(by: determinant, usage: &execution)
        let b = try triple(x, displacement, z, using: &execution).divided(by: determinant, usage: &execution)
        let c = try triple(x, y, displacement, using: &execution).divided(by: determinant, usage: &execution)
        let first = try a.outwardInterval(usage: &execution), second = try b.outwardInterval(usage: &execution), third = try c.outwardInterval(usage: &execution)
        let candidate = Point3D(x: first.lower * 0.5 + first.upper * 0.5,
            y: second.lower * 0.5 + second.upper * 0.5, z: third.lower * 0.5 + third.upper * 0.5)
        guard candidate.isFinite else { throw IndependentShapeExchangeError.invalidAssociation("Original affine trim inverse has no finite candidate.") }
        return candidate
    }

    private func triple(_ a: [ExactRationalCoefficient], _ b: [ExactRationalCoefficient],
                        _ c: [ExactRationalCoefficient], using execution: inout OriginalQueryExecution) throws -> ExactRationalCoefficient {
        var result = ExactRationalCoefficient.zero
        for index in 0..<3 {
            try execution.consumeWork(1)
            let j = (index + 1) % 3, k = (index + 2) % 3
            let cross = try b[j].multiplied(by: c[k], usage: &execution)
                .subtracting(b[k].multiplied(by: c[j], usage: &execution), usage: &execution)
            result = try result.adding(a[index].multiplied(by: cross, usage: &execution), usage: &execution)
        }
        return result
    }
}
