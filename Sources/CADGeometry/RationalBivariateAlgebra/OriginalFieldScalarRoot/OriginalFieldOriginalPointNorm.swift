/// Descends an ORIGINAL two-coordinate field to a rational scalar polynomial.
struct OriginalFieldOriginalPointNorm {
    static func descending<B: ExactScalarAdmission & ~Copyable>(_ original: OriginalSingularFieldPolynomial,
        at root: ExactAlgebraicPairAuthority, maximumDepth: Int, usage: inout B) throws -> ExactBivariatePolynomial {
        var fiber = root.fiber
        var projection = root.projectionRoot.polynomial
        try RationalAlgebraStorage.retain(original.coefficients.count, of: ExactBivariatePolynomial.self, usage: &usage)
        var cleared: [ExactBivariatePolynomial] = []; cleared.reserveCapacity(original.coefficients.count)
        for coefficient in original.coefficients {
            guard case .original(_, let denominator) = coefficient.storage else {
                throw rationalAlgebraFailure("Original point norm contains an unrelated extension coefficient.")
            }
            if case .zero = try root.sign(of: denominator, maximumDepth: maximumDepth, usage: &usage) {
                throw rationalAlgebraFailure("Original point norm has a pole at its retained real point.")
            }
            let poles = try ExactAlgebraicFiberPolynomial(source: denominator, at: root.projectionRoot,
                maximumDepth: maximumDepth, usage: &usage)
            while true {
                let shared = try ExactAlgebraicFiberPolynomial.gcd(fiber, poles,
                    maximumDepth: maximumDepth, usage: &usage)
                if shared.degree <= 0 { break }
                let excluded = try originalNumerator(shared, usage: &usage)
                if case .zero = try root.sign(of: excluded, maximumDepth: maximumDepth, usage: &usage) {
                    throw rationalAlgebraFailure("Original point norm saturation would remove its retained real point.")
                }
                let division = try fiber.divided(by: shared, maximumDepth: maximumDepth, usage: &usage)
                guard division.remainder.isZero, division.quotient.degree < fiber.degree else {
                    throw rationalAlgebraFailure("Original point norm did not remove its excluded pole conjugates.")
                }
                fiber = division.quotient
            }
        }
        for index in original.coefficients.indices {
            guard case .original(let numerator, _) = original.coefficients[index].storage else {
                throw rationalAlgebraFailure("Original point norm lost a retained source numerator.")
            }
            var value = numerator
            for other in original.coefficients.indices where other != index {
                guard case .original(_, let denominator) = original.coefficients[other].storage else {
                    throw rationalAlgebraFailure("Original point norm lost a retained source denominator.")
                }
                value = try value.multiplied(by: denominator, usage: &usage)
            }
            cleared.append(value)
        }
        let ring = try ExactSurfaceCoefficientPolynomial(coefficients: cleared, usage: &usage)
        let rawFiber = try originalNumerator(fiber, usage: &usage)
        let first = try ExactSurfaceLocusParameterProjection.reordered(locus: rawFiber, usage: &usage)
        let second = try ExactSurfaceLocusParameterProjection.reordered(common: ring, usage: &usage)
        let equation = try ExactSurfaceCoefficientResultant().eliminatingParameter(first, second, usage: &usage)
        guard !equation.isZero else { throw rationalAlgebraFailure("Original point norm has a nullified transverse resultant.") }
        let gcd = ExactBivariateGCD()
        for coefficient in fiber.coefficients.values {
            if case .zero = try root.projectionRoot.sign(of: coefficient.denominator,
                maximumDepth: maximumDepth, usage: &usage) {
                throw rationalAlgebraFailure("Original norm fiber coefficient has a pole at its retained projection.")
            }
            projection = try projection.dividedExactly(by: gcd.univariateGCD(projection,
                coefficient.denominator, usage: &usage), usage: &usage)
        }
        let content = try gcd.content(equation, usage: &usage)
        let absent = try gcd.univariateGCD(projection, content, usage: &usage)
        if case .zero = try root.projectionRoot.sign(of: absent, maximumDepth: maximumDepth, usage: &usage) {
            throw rationalAlgebraFailure("Original point norm nullifies at its selected projection embedding.")
        }
        projection = try projection.dividedExactly(by: absent, usage: &usage)
        guard projection.uDegree > 0, case .zero = try root.projectionRoot.sign(of: projection,
            maximumDepth: maximumDepth, usage: &usage) else {
            throw rationalAlgebraFailure("Original norm saturation lost its selected projection relation.")
        }
        let result = try ExactBivariateResultant().eliminatingV(projection.exchangedAxes(usage: &usage),
            equation.exchangedAxes(usage: &usage), usage: &usage)
        guard !result.isZero, result.vDegree <= 0, result.uDegree > 0 else {
            throw rationalAlgebraFailure("Original two-coordinate norm lacks a nonconstant rational scalar law.")
        }
        return result
    }

    private static func originalNumerator<B: ExactScalarAdmission & ~Copyable>(_ fiber: ExactAlgebraicFiberPolynomial,
        usage: inout B) throws -> ExactBivariatePolynomial {
        var result = ExactBivariatePolynomial.zero
        try RationalAlgebraStorage.retain(fiber.coefficients.count, of: Int.self, usage: &usage)
        let degrees = fiber.coefficients.keys.sorted()
        try usage.consumeWork(try rationalAlgebraCount(degrees.count, max(1, degrees.count), multiply: true))
        for degree in degrees {
            guard let coefficient = fiber.coefficients[degree] else { throw rationalAlgebraFailure("Original norm missing fiber coefficient.") }
            var term = coefficient.numerator
            for otherDegree in degrees where otherDegree != degree {
                guard let other = fiber.coefficients[otherDegree] else { throw rationalAlgebraFailure("Original norm missing denominator coefficient.") }
                term = try term.multiplied(by: other.denominator, usage: &usage)
            }
            result = try result.adding(term.shiftedV(degree, usage: &usage), usage: &usage)
        }
        return result
    }
}
