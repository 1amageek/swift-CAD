/// Exact parameter projection of a retained original quotient common fiber.
package struct ExactSurfaceLocusParameterProjection: Sendable {
    package enum Kind: Sendable {
        case wholeParameterFiber
        case noGenericFiber
        case projected(ExactBivariatePolynomial)
        case coordinateSystem(locus: ExactBivariatePolynomial, common: ExactBivariatePolynomial)
    }
    package let component: ExactSurfaceLocusCommonFiber.Component
    /// Coefficients in powers of original v; each coefficient is in Q[u,s].
    package let originalLocusInV: ExactSurfaceCoefficientPolynomial
    package let originalCommonInV: ExactSurfaceCoefficientPolynomial
    package let kind: Kind

    package init<B: ExactScalarAdmission & ~Copyable>(component: ExactSurfaceLocusCommonFiber.Component,
        usage: inout B) throws {
        self.component = component
        originalLocusInV = try Self.reordered(locus: component.originalLocus, usage: &usage)
        originalCommonInV = try Self.reordered(common: component.common, usage: &usage)
        if component.common.isZero { kind = .wholeParameterFiber }
        else if component.common.degree == 0 { kind = .noGenericFiber }
        else if originalLocusInV.degree <= 0, originalCommonInV.degree <= 0 {
            guard let locus = originalLocusInV.coefficients.first,
                let common = originalCommonInV.coefficients.first else {
                throw rationalAlgebraFailure("Original projected coordinate system lacks its nonzero source laws.")
            }
            kind = .coordinateSystem(locus: locus, common: common)
        } else {
            kind = .projected(try ExactSurfaceCoefficientResultant().eliminatingParameter(
                originalLocusInV, originalCommonInV, usage: &usage))
        }
    }
    package static func reordered<B: ExactScalarAdmission & ~Copyable>(locus: ExactBivariatePolynomial,
        usage: inout B) throws -> ExactSurfaceCoefficientPolynomial {
        let count = try rationalAlgebraCount(max(0, locus.vDegree), 1)
        try RationalAlgebraStorage.retain(count, of: ExactBivariatePolynomial.self, usage: &usage)
        var values: [ExactBivariatePolynomial] = []; values.reserveCapacity(count)
        for index in 0..<count {
            values.append(try locus.coefficient(ofV: index, usage: &usage))
        }
        return try .init(coefficients: values, usage: &usage)
    }
    package static func reordered<B: ExactScalarAdmission & ~Copyable>(common: ExactSurfaceCoefficientPolynomial,
        usage: inout B) throws -> ExactSurfaceCoefficientPolynomial {
        var degree = -1
        for coefficient in common.coefficients { try usage.consumeWork(1); degree = max(degree, coefficient.vDegree) }
        let count = degree < 0 ? 0 : try rationalAlgebraCount(degree, 1)
        try RationalAlgebraStorage.retain(count, of: ExactBivariatePolynomial.self, usage: &usage)
        var values = [ExactBivariatePolynomial](repeating: .zero, count: count)
        for sourceParameterPower in common.coefficients.indices {
            for (power, value) in try common.coefficients[sourceParameterPower].orderedTerms(usage: &usage) {
                try usage.consumeWork(1)
                try RationalAlgebraStorage.retain(1, of: (ExactBivariatePolynomial.Power, ExactRationalCoefficient).self, usage: &usage)
                let term = try ExactBivariatePolynomial([.init(u: power.u, v: sourceParameterPower): value])
                values[power.v] = try values[power.v].adding(term, usage: &usage)
            }
        }
        return try .init(coefficients: values, usage: &usage)
    }
}
