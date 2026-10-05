import CADCore

/// Whole original rational coefficient bound on a finite native rectangle.
extension ExactBivariatePolynomial {
    package func exactAbsoluteBound<B: RationalAlgebraAdmitting>(over box: SurfaceParameterBox,
        usage: inout B) throws -> ExactRationalCoefficient {
        if isZero { return .zero }
        func magnitude(_ value: ExactRationalCoefficient) -> ExactRationalCoefficient {
            value.isNegative ? value.negated : value
        }
        func powers(_ range: ScalarInterval, degree: Int, usage: inout B) throws -> [ExactRationalCoefficient] {
            let low = try magnitude(.originalDouble(range.lower, usage: &usage))
            let high = try magnitude(.originalDouble(range.upper, usage: &usage))
            let bound = try high.subtracting(low, usage: &usage).isPositive ? high : low
            let count = try rationalAlgebraCount(max(0, degree), 1)
            try usage.retainExactStorage(count)
            var values: [ExactRationalCoefficient] = [.one]
            if degree > 0 { for _ in 0..<degree {
                values.append(try values[values.count - 1].multiplied(by: bound, usage: &usage))
            } }
            return values
        }
        let u = try powers(box.u, degree: uDegree, usage: &usage)
        let v = try powers(box.v, degree: vDegree, usage: &usage)
        var bound = ExactRationalCoefficient.zero
        for (power, coefficient) in try orderedTerms(usage: &usage) {
            bound = try bound.adding(magnitude(coefficient).multiplied(by: u[power.u], usage: &usage)
                .multiplied(by: v[power.v], usage: &usage), usage: &usage)
        }
        return bound
    }
}
