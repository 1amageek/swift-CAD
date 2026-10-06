/// Exact coordinate transport retaining an already proved original system point.
package extension ExactBivariateSystemRoot {
    func originalFiberNumerator<B: RationalAlgebraAdmitting>(usage: inout B) throws -> ExactBivariatePolynomial {
        var result = ExactBivariatePolynomial.zero
        for (degree, coefficient) in fiber.coefficients {
            var term = coefficient.numerator
            for (otherDegree, other) in fiber.coefficients where otherDegree != degree {
                term = try term.multiplied(by: other.denominator, usage: &usage)
            }
            try usage.retainExactStorage(1)
            let power = try ExactBivariatePolynomial([.init(u: 0, v: degree): .one])
            result = try result.adding(term.multiplied(by: power, usage: &usage), usage: &usage)
        }
        return result
    }

    func originalCoordinate<B: RationalAlgebraAdmitting>(alongU: Bool, maximumDepth: Int,
        usage: inout B) throws -> ExactMonotoneGraphEndpoint {
        if alongU { return .algebraic(projectionRoot) }
        let gcd = ExactBivariateGCD()
        var projection = projectionRoot.polynomial
        for coefficient in fiber.coefficients.values {
            guard case .zero = try projectionRoot.sign(of: coefficient.denominator,
                maximumDepth: maximumDepth, usage: &usage) else {
                let poles = try gcd.univariateGCD(projection, coefficient.denominator, usage: &usage)
                projection = try projection.dividedExactly(by: poles, usage: &usage)
                continue
            }
            throw rationalAlgebraFailure("Original point fiber denominator vanishes at its retained source root.")
        }
        let originalFiber = try originalFiberNumerator(usage: &usage)
        let content = try gcd.content(originalFiber, usage: &usage)
        let absent = try gcd.univariateGCD(projection, content, usage: &usage)
        projection = try projection.dividedExactly(by: absent, usage: &usage)
        guard projection.uDegree > 0,
            case .zero = try projectionRoot.sign(of: projection, maximumDepth: maximumDepth, usage: &usage),
            case .zero = try sign(of: originalFiber, maximumDepth: maximumDepth, usage: &usage) else {
            throw rationalAlgebraFailure("Original coordinate transport lost its retained source point.")
        }
        let equation = try ExactBivariateResultant().eliminatingV(
            projection.exchangedAxes(usage: &usage), originalFiber.exchangedAxes(usage: &usage), usage: &usage)
        guard !equation.isZero, equation.uDegree > 0, equation.vDegree <= 0 else {
            throw rationalAlgebraFailure("Original coordinate resultant has no finite retained point law.")
        }
        let sequence = try ExactUnivariateSturmSequence(equation, usage: &usage)
        var retained = self
        let two = try ExactRationalCoefficient.natural(2, usage: &usage)
        while true {
            let bound = retained.fiberRoot
            let count = try sequence.count(lower: bound.lower, upper: bound.upper,
                excludesLower: bound.excludesLower, excludesUpper: bound.excludesUpper, usage: &usage)
            guard count > 0 else { throw rationalAlgebraFailure("Original point coordinate has no root in its retained fiber enclosure.") }
            if count == 1 {
                let isolation = ExactUnivariateRootIsolator.Root(lower: bound.lower, upper: bound.upper,
                    isRationalStation: bound.lower == bound.upper,
                    isolationDepth: max(retained.projectionRoot.isolation.isolationDepth, bound.isolationDepth),
                    excludesLowerEndpoint: bound.excludesLower, excludesUpperEndpoint: bound.excludesUpper)
                return try .algebraic(ExactAlgebraicRealRoot(polynomial: sequence.source, isolation: isolation, usage: &usage))
            }
            let width = try bound.upper.subtracting(bound.lower, usage: &usage)
            guard width.isPositive else { throw rationalAlgebraFailure("Original point coordinate root count contradicts its exact singleton.") }
            let uWidth = try retained.projectionRoot.isolation.upper.subtracting(retained.projectionRoot.isolation.lower, usage: &usage)
            retained = try retained.refined(maximumUWidth: uWidth.isPositive ? uWidth : .one,
                maximumVWidth: width.divided(by: two, usage: &usage), maximumDepth: maximumDepth, usage: &usage)
        }
    }
}
