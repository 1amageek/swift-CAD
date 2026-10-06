import CADCore

/// Positive original quotient proofs for an exactly nominated seam or corner.
struct OriginalCoonsRationalBoundaryContactProof {
    private struct Directions {
        let free: [OutwardScalarInterval]
        let transverse: [OutwardScalarInterval]
        let normal: [OutwardScalarInterval]
    }

    func provesSeam<B: RationalAlgebraAdmitting>(first: [OriginalCoonsRationalDifferentialAtlas.Field],
        second: [OriginalCoonsRationalDifferentialAtlas.Field],
        firstBoundary: SurfaceParameterBoundary, secondBoundary: SurfaceParameterBoundary,
        usage: inout B) throws -> Bool {
        let count = first.count.addingReportingOverflow(second.count)
        guard !count.overflow else { throw GeometryConversionError.resourceLimitExceeded("Original seam field count overflows.") }
        let slots = count.partialValue.multipliedReportingOverflow(by: 13)
        guard !slots.overflow else { throw GeometryConversionError.resourceLimitExceeded("Original seam field storage overflows.") }
        try usage.retainExactStorage(slots.partialValue)
        var directions: [Directions] = []
        directions.reserveCapacity(count.partialValue)
        for (fields, boundary, index) in [(first, firstBoundary, 0), (second, secondBoundary, 1)] {
            let fixedU = boundary == .uLower || boundary == .uUpper
            let upper = boundary == .uUpper || boundary == .vUpper
            let inward = upper == (index == 0) ? 1.0 : -1.0
            for field in fields {
                try usage.consumeExactWork(12)
                directions.append(Directions(free: fixedU ? field.tangentV : field.tangentU,
                    transverse: (fixedU ? field.tangentU : field.tangentV).map { $0 * .exact(inward) },
                    normal: field.normal.map { $0 * .exact((fixedU ? -1.0 : 1.0) * inward) }))
            }
        }
        guard !directions.isEmpty else { return false }
        // Projection coefficients are finite candidates only. Every original
        // quotient field below must admit the same principal-minor signs.
        for seed in directions {
            try usage.consumeExactWork(48)
            let a = midpoint(seed.free), b = midpoint(seed.transverse)
            let aa = a.dot(a), ab = a.dot(b), bb = b.dot(b), determinant = aa * bb - ab * ab
            guard determinant.isFinite, determinant > 0 else { continue }
            let firstAxis = (a * bb - b * ab) * (1 / determinant)
            let secondAxis = (b * aa - a * ab) * (1 / determinant)
            guard finite(firstAxis), finite(secondAxis) else { continue }
            let normalAxis = firstAxis.cross(secondAxis)
            var firstSign: Int?, secondSign: Int?, normalSign: Int?
            var admitted = true
            for field in directions {
                try usage.consumeExactWork(48)
                guard let u = sign(project(field.free, firstAxis)),
                      let v = sign(project(field.transverse, secondAxis)),
                      let n = sign(project(field.normal, normalAxis)), u * v * n > 0,
                      firstSign == nil || firstSign == u,
                      secondSign == nil || secondSign == v,
                      normalSign == nil || normalSign == n else { admitted = false; break }
                firstSign = u; secondSign = v; normalSign = n
            }
            if admitted { return true }
        }
        return false
    }

    func provesCorner<B: RationalAlgebraAdmitting>(first: [OriginalCoonsRationalDifferentialAtlas.Field],
        second: [OriginalCoonsRationalDifferentialAtlas.Field], firstCorner: Point2D, secondCorner: Point2D,
        usage: inout B) throws -> Bool {
        guard !first.isEmpty, !second.isEmpty else { return false }
        let total = first.count.addingReportingOverflow(second.count)
        guard !total.overflow else { throw GeometryConversionError.resourceLimitExceeded("Original corner field count overflows.") }
        let slots = total.partialValue.multipliedReportingOverflow(by: 8)
        guard !slots.overflow else { throw GeometryConversionError.resourceLimitExceeded("Original corner cone storage overflows.") }
        try usage.retainExactStorage(slots.partialValue)
        var firstCone: [[OutwardScalarInterval]] = [], secondCone: [[OutwardScalarInterval]] = []
        for field in first {
            try usage.consumeExactWork(6)
            firstCone.append(field.tangentU.map { $0 * .exact(firstCorner.x == 0 ? 1 : -1) })
            firstCone.append(field.tangentV.map { $0 * .exact(firstCorner.y == 0 ? 1 : -1) })
        }
        for field in second {
            try usage.consumeExactWork(6)
            secondCone.append(field.tangentU.map { $0 * .exact(secondCorner.x == 0 ? 1 : -1) })
            secondCone.append(field.tangentV.map { $0 * .exact(secondCorner.y == 0 ? 1 : -1) })
        }
        for a in firstCone {
            for b in secondCone {
                try usage.consumeExactWork(6)
                let candidate = midpoint(a) - midpoint(b)
                guard finite(candidate) else { continue }
                var admitted = true
                for ray in firstCone {
                    try usage.consumeExactWork(12)
                    if project(ray, candidate).lower <= 0 { admitted = false; break }
                }
                if !admitted { continue }
                for ray in secondCone {
                    try usage.consumeExactWork(12)
                    if project(ray, candidate).upper >= 0 { admitted = false; break }
                }
                if admitted { return true }
            }
        }
        return false
    }

    private func midpoint(_ vector: [OutwardScalarInterval]) -> Vector3D {
        .init(x: vector[0].midpoint, y: vector[1].midpoint, z: vector[2].midpoint)
    }
    private func finite(_ vector: Vector3D) -> Bool {
        vector.x.isFinite && vector.y.isFinite && vector.z.isFinite
    }
    private func project(_ vector: [OutwardScalarInterval], _ axis: Vector3D) -> OutwardScalarInterval {
        vector[0] * .exact(axis.x) + vector[1] * .exact(axis.y) + vector[2] * .exact(axis.z)
    }
    private func sign(_ interval: OutwardScalarInterval) -> Int? {
        if interval.lower > 0 { return 1 }; if interval.upper < 0 { return -1 }; return nil
    }
}
