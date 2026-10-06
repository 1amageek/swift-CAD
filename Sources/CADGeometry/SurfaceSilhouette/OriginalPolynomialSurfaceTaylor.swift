import CADCore

/// Requested-order Taylor coefficients of three original exact native polynomials.
struct OriginalPolynomialSurfaceTaylor {
    static func vector<B: RationalAlgebraAdmitting>(polynomials: [ExactBivariatePolynomial],
        over box: SurfaceParameterBox, throughOrder order: Int,
        tolerance: ModelingTolerance, usage: inout B) throws -> SurfaceAreaIntervalTaylorVectorJet {
        guard polynomials.count == 3, order >= 0 else {
            throw rationalAlgebraFailure("Original polynomial Taylor vector needs three coefficients and a nonnegative order.")
        }
        func scalar(_ polynomial: ExactBivariatePolynomial,
            usage: inout B) throws -> SurfaceAreaIntervalTaylorScalarJet {
            func storage(_ bytes: Int) throws { try RationalAlgebraStorage.retainBytes(bytes, usage: &usage) }
            var value = try withoutActuallyEscaping(storage) { borrowedStorage in
                try SurfaceAreaIntervalTaylorScalarJet(order: order, tolerance: tolerance,
                    consumeWork: { try usage.consumeExactWork(1) }, consumeStorage: borrowedStorage)
            }
            var uDerivative = polynomial, uScale = ExactRationalCoefficient.one
            for u in 0...order {
                var derivative = uDerivative, scale = uScale
                for v in 0...(order - u) {
                    let coefficient = try derivative.scaled(by: scale, usage: &usage).enclosure(over: box, usage: &usage)
                    try usage.consumeExactWork(1); try value.set(coefficient, u, v)
                    if v < order - u {
                        derivative = try derivative.differentiated(alongU: false, usage: &usage)
                        scale = try scale.divided(by: .natural(v + 1, usage: &usage), usage: &usage)
                    }
                }
                if u < order {
                    uDerivative = try uDerivative.differentiated(alongU: true, usage: &usage)
                    uScale = try uScale.divided(by: .natural(u + 1, usage: &usage), usage: &usage)
                }
            }
            return value
        }
        return try .init(x: scalar(polynomials[0], usage: &usage),
            y: scalar(polynomials[1], usage: &usage), z: scalar(polynomials[2], usage: &usage))
    }

    static func normalized<B: RationalAlgebraAdmitting>(_ original: SurfaceAreaIntervalTaylorVectorJet,
        usage: inout B) throws -> SurfaceAreaIntervalTaylorVectorJet {
        let bounds = try IntervalVector3DBounds(x: original.x.coefficient(0, 0),
            y: original.y.coefficient(0, 0), z: original.z.coefficient(0, 0))
        let lower = bounds.lengthLowerBound, upper = bounds.lengthUpperBound
        guard lower.isFinite, upper.isFinite, lower > 0 else {
            throw KernelError(phase: .geometry, code: .singularGeometry, tolerance: original.x.tolerance,
                message: "Original factored normal is not certified nonzero on the whole requested native box.")
        }
        func work() throws { try usage.consumeExactWork(1) }
        func storage(_ bytes: Int) throws { try RationalAlgebraStorage.retainBytes(bytes, usage: &usage) }
        return try withoutActuallyEscaping(storage) { storage in
            var square = try original.x.multiplied(by: original.x, consumeWork: work, consumeStorage: storage)
                .adding(original.y.multiplied(by: original.y, consumeWork: work, consumeStorage: storage), consumeWork: work, consumeStorage: storage)
                .adding(original.z.multiplied(by: original.z, consumeWork: work, consumeStorage: storage), consumeWork: work, consumeStorage: storage)
            let positive = OutwardScalarInterval(lower: lower, upper: upper)
            guard let value = try square.coefficient(0, 0).intersection(with: positive * positive) else {
                throw rationalAlgebraFailure("Original normal square contradicts its strict whole vector norm.")
            }
            try usage.consumeExactWork(1); try square.set(value, 0, 0)
            let reciprocal = try square.squareRoot(consumeWork: work, consumeStorage: storage).reciprocal(consumeWork: work, consumeStorage: storage)
            return try original.multiplied(by: reciprocal, consumeWork: work, consumeStorage: storage)
        }
    }
}
