import CADCore

/// Requested-order Taylor coefficients of three original exact native polynomials.
struct OriginalPolynomialSurfaceTaylor {
    static func vector<B: ExactScalarAdmission & ~Copyable>(polynomials: [ExactBivariatePolynomial],
        over box: SurfaceParameterBox, throughOrder order: Int,
        tolerance: ModelingTolerance, usage: inout B) throws -> SurfaceAreaIntervalTaylorVectorJet {
        try vector(polynomials: polynomials[...], over: box, throughOrder: order,
            tolerance: tolerance, usage: &usage)
    }

    static func vector<B: ExactScalarAdmission & ~Copyable>(polynomials: ArraySlice<ExactBivariatePolynomial>,
        over box: SurfaceParameterBox, throughOrder order: Int,
        tolerance: ModelingTolerance, usage: inout B) throws -> SurfaceAreaIntervalTaylorVectorJet {
        guard polynomials.count == 3, order >= 0 else {
            throw rationalAlgebraFailure("Original polynomial Taylor vector needs three coefficients and a nonnegative order.")
        }
        func scalar(_ polynomial: ExactBivariatePolynomial,
            usage: inout B) throws -> SurfaceAreaIntervalTaylorScalarJet {
            var value = try SurfaceAreaIntervalTaylorScalarJet(order: order, tolerance: tolerance, using: &usage)
            var uDerivative = polynomial, uScale = ExactRationalCoefficient.one
            for u in 0...order {
                var derivative = uDerivative, scale = uScale
                for v in 0...(order - u) {
                    let coefficient = try derivative.scaled(by: scale, usage: &usage).enclosure(over: box, usage: &usage)
                    try usage.consumeWork(1); try value.set(coefficient, u, v)
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
        let first = polynomials.startIndex
        return try .init(x: scalar(polynomials[first], usage: &usage),
            y: scalar(polynomials[first + 1], usage: &usage), z: scalar(polynomials[first + 2], usage: &usage))
    }

    static func normalized<B: ExactScalarAdmission & ~Copyable>(_ original: SurfaceAreaIntervalTaylorVectorJet,
        usage: inout B) throws -> SurfaceAreaIntervalTaylorVectorJet {
        let bounds = try IntervalVector3DBounds(x: original.x.coefficient(0, 0),
            y: original.y.coefficient(0, 0), z: original.z.coefficient(0, 0))
        let lower = bounds.lengthLowerBound, upper = bounds.lengthUpperBound
        guard lower.isFinite, upper.isFinite, lower > 0 else {
            throw KernelError(phase: .geometry, code: .singularGeometry, tolerance: original.x.tolerance,
                message: "Original factored normal is not certified nonzero on the whole requested native box.")
        }
            var square = try original.x.multiplied(by: original.x, using: &usage)
                .adding(original.y.multiplied(by: original.y, using: &usage), using: &usage)
                .adding(original.z.multiplied(by: original.z, using: &usage), using: &usage)
            let positive = OutwardScalarInterval(lower: lower, upper: upper)
            guard let value = try square.coefficient(0, 0).intersection(with: positive * positive) else {
                throw rationalAlgebraFailure("Original normal square contradicts its strict whole vector norm.")
            }
            try usage.consumeWork(1); try square.set(value, 0, 0)
            let reciprocal = try square.squareRoot(using: &usage).reciprocal(using: &usage)
            return try original.multiplied(by: reciprocal, using: &usage)
    }
}
