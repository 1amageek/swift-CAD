/// Preserves an original rational law in a retained descendant ordered field.
extension OriginalSingularFieldPlanePolynomial {
    package static func original<B: ExactScalarAdmission & ~Copyable>(_ source: ExactBivariatePolynomial,
        in context: OriginalSingularFieldContext, maximumDepth: Int, usage: inout B) throws -> Self {
        try RationalAlgebraStorage.retain(source.coefficients.count,
            of: (ExactBivariatePolynomial.Power, OriginalSingularFieldElement).self, usage: &usage)
        var coefficients: [ExactBivariatePolynomial.Power: OriginalSingularFieldElement] = [:]
        for (power, value) in try source.orderedTerms(usage: &usage) {
            coefficients[power] = try .constant(value, in: context, maximumDepth: maximumDepth, usage: &usage)
        }
        return try Self(context: context, coefficients: coefficients, maximumDepth: maximumDepth, usage: &usage)
    }
}

extension OriginalSingularFieldPlanePolynomial {
    package func differentiated<B: ExactScalarAdmission & ~Copyable>(alongU: Bool,
        maximumDepth: Int, usage: inout B) throws -> Self {
        try RationalAlgebraStorage.retain(coefficients.count,
            of: (ExactBivariatePolynomial.Power, OriginalSingularFieldElement).self, usage: &usage)
        var result: [ExactBivariatePolynomial.Power: OriginalSingularFieldElement] = [:]
        for (power, value) in try orderedTerms(usage: &usage) {
            try usage.consumeWork(1)
            let degree = alongU ? power.u : power.v
            if degree == 0 { continue }
            let scale = try OriginalSingularFieldElement.constant(.natural(degree, usage: &usage),
                in: context, maximumDepth: maximumDepth, usage: &usage)
            result[try .init(u: power.u - (alongU ? 1 : 0),
                v: power.v - (alongU ? 0 : 1))] = try value.multiplied(by: scale,
                    maximumDepth: maximumDepth, usage: &usage)
        }
        return try Self(context: context, coefficients: result,
            maximumDepth: maximumDepth, usage: &usage)
    }
}
