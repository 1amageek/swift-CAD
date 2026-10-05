/// Original polynomial in a separate parameter over the exact Q[u,v] ring.
package struct ExactSurfaceCoefficientPolynomial: Sendable {
    package let coefficients: [ExactBivariatePolynomial]
    package var degree: Int { coefficients.count - 1 }
    package var isZero: Bool { coefficients.isEmpty }

    package init<B: RationalAlgebraAdmitting>(coefficients: [ExactBivariatePolynomial],
        usage: inout B) throws {
        var count = coefficients.count
        while count > 0 {
            try usage.consumeExactWork(1)
            if !coefficients[count - 1].isZero { break }
            count -= 1
        }
        if count == coefficients.count { self.coefficients = coefficients }
        else {
            try RationalAlgebraStorage.retain(count, of: ExactBivariatePolynomial.self, usage: &usage)
            self.coefficients = Array(coefficients.prefix(count))
        }
    }

    /// Uses the issued UV pair directly; no equation solving or root selection is repeated.
    package func specialized<B: RationalAlgebraAdmitting>(
        in context: OriginalSingularFieldContext, maximumDepth: Int, usage: inout B
    ) throws -> OriginalSingularFieldPolynomial {
        guard case .original = context.source else {
            throw rationalAlgebraFailure("Projected parameter specialization needs its retained original UV pair.")
        }
        try RationalAlgebraStorage.retain(coefficients.count, of: OriginalSingularFieldElement.self, usage: &usage)
        var values: [OriginalSingularFieldElement] = []; values.reserveCapacity(coefficients.count)
        for coefficient in coefficients {
            try usage.consumeExactWork(1)
            values.append(try .original(coefficient, in: context, usage: &usage))
        }
        return try .init(context: context, coefficients: values, maximumDepth: maximumDepth, usage: &usage)
    }
}
