/// Successive ORIGINAL defining-relation norms, preserving the selected real embedding.
struct OriginalFieldPolynomialNorm {
    static func rationalNorm<B: RationalAlgebraAdmitting>(_ original: OriginalSingularFieldPolynomial,
        maximumDepth: Int, usage: inout B) throws -> ExactBivariatePolynomial {
        var polynomial = original
        while true {
            try usage.consumeExactWork(1)
            guard !polynomial.isZero else { throw rationalAlgebraFailure("Original field norm is identically zero.") }
            switch polynomial.context.source {
            case .rational:
                try RationalAlgebraStorage.retain(polynomial.coefficients.count,
                    of: (ExactBivariatePolynomial.Power, ExactRationalCoefficient).self, usage: &usage)
                var values: [ExactBivariatePolynomial.Power: ExactRationalCoefficient] = [:]
                for index in polynomial.coefficients.indices {
                    guard let value = try polynomial.coefficients[index].rationalValue(usage: &usage) else {
                        throw rationalAlgebraFailure("Original rational norm retains a foreign field coefficient.")
                    }
                    if !value.isZero { values[try .init(u: index, v: 0)] = value }
                }
                return ExactBivariatePolynomial(values)
            case .original(let root):
                return try OriginalFieldOriginalPointNorm.descending(polynomial, at: root,
                    maximumDepth: maximumDepth, usage: &usage)
            case .extended(let root):
                polynomial = try descending(polynomial, through: root, maximumDepth: maximumDepth, usage: &usage)
            }
        }
    }

    private static func descending<B: RationalAlgebraAdmitting>(_ original: OriginalSingularFieldPolynomial,
        through root: OriginalSingularFieldRoot, maximumDepth: Int, usage: inout B)
        throws -> OriginalSingularFieldPolynomial {
        let parent = root.polynomial.context
        var source = root.polynomial
        for coefficient in original.coefficients {
            guard case .extended(_, let denominator) = coefficient.storage else {
                throw rationalAlgebraFailure("Original norm coefficient contradicts its extension owner.")
            }
            guard case .zero = try root.sign(of: denominator, maximumDepth: maximumDepth, usage: &usage) else {
                while true {
                    let poles = try OriginalSingularFieldPolynomial.gcd(source, denominator,
                        maximumDepth: maximumDepth, usage: &usage)
                    if poles.degree <= 0 { break }
                    if case .zero = try root.sign(of: poles, maximumDepth: maximumDepth, usage: &usage) {
                        throw rationalAlgebraFailure("Original norm saturation would remove its selected real embedding.")
                    }
                    let division = try source.divided(by: poles, maximumDepth: maximumDepth, usage: &usage)
                    guard division.remainder.isZero, division.quotient.degree < source.degree else {
                        throw rationalAlgebraFailure("Original norm pole saturation did not lower the exact defining degree.")
                    }
                    source = division.quotient
                }
                continue
            }
            throw rationalAlgebraFailure("Original norm coefficient denominator vanishes at the selected real embedding.")
        }
        try RationalAlgebraStorage.retain(source.coefficients.count,
            of: (ExactBivariatePolynomial.Power, OriginalSingularFieldElement).self, usage: &usage)
        var relation: [ExactBivariatePolynomial.Power: OriginalSingularFieldElement] = [:]
        for index in source.coefficients.indices {
            relation[try .init(u: 0, v: index)] = source.coefficients[index]
        }
        var values: [ExactBivariatePolynomial.Power: OriginalSingularFieldElement] = [:]
        for index in original.coefficients.indices {
            guard case .extended(let numerator, _) = original.coefficients[index].storage else {
                throw rationalAlgebraFailure("Original norm numerator lacks its actual defining extension.")
            }
            var cleared = numerator
            for other in original.coefficients.indices where other != index {
                guard case .extended(_, let denominator) = original.coefficients[other].storage else {
                    throw rationalAlgebraFailure("Original norm clearing lost a source denominator.")
                }
                cleared = try cleared.multiplied(by: denominator, maximumDepth: maximumDepth, usage: &usage)
            }
            for power in cleared.coefficients.indices {
                try usage.consumeExactWork(1)
                try RationalAlgebraStorage.retain(1,
                    of: (ExactBivariatePolynomial.Power, OriginalSingularFieldElement).self, usage: &usage)
                values[try .init(u: index, v: power)] = cleared.coefficients[power]
            }
        }
        let first = try OriginalSingularFieldPlanePolynomial(context: parent, coefficients: relation,
            maximumDepth: maximumDepth, usage: &usage)
        let second = try OriginalSingularFieldPlanePolynomial(context: parent, coefficients: values,
            maximumDepth: maximumDepth, usage: &usage)
        let result = try OriginalSingularFieldResultant.eliminatingV(first, second,
            maximumDepth: maximumDepth, usage: &usage)
        guard !result.isZero else { throw rationalAlgebraFailure("Original extension norm has a nullified resultant.") }
        return result
    }
}
