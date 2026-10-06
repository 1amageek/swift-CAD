extension OriginalSingularFieldRoot {
    /// Reuses rational Newton localization without changing the retained original field law.
    func rationalRefinedOnce<B: RationalAlgebraAdmitting>(maximumDepth: Int,
        usage: inout B) throws -> Self? {
        var coefficients: [ExactBivariatePolynomial.Power: ExactRationalCoefficient] = [:]
        for (power, coefficient) in polynomial.coefficients.enumerated() {
            try usage.consumeExactWork(1)
            guard let value = try coefficient.rationalValue(usage: &usage) else { return nil }
            if value.isZero { continue }
            try RationalAlgebraStorage.retain(1,
                of: (ExactBivariatePolynomial.Power, ExactRationalCoefficient).self, usage: &usage)
            coefficients[try .init(u: power, v: 0)] = value
        }
        let exact = ExactBivariatePolynomial(coefficients)
        guard exact.uDegree > 0 else {
            throw rationalAlgebraFailure("Retained field scalar root lost its nonconstant rational law.")
        }
        var admission = OriginalScalarRootDomainAdmission(base: usage, domain: admissionDomain)
        defer { usage = admission.base }
        let retained = try ExactAlgebraicRealRoot(polynomial: exact,
            isolation: .init(lower: isolation.lower, upper: isolation.upper,
                isRationalStation: isolation.lower == isolation.upper, isolationDepth: isolation.depth,
                excludesLowerEndpoint: isolation.excludesLower,
                excludesUpperEndpoint: isolation.excludesUpper), usage: &admission)
        let width = try isolation.upper.subtracting(isolation.lower, usage: &admission)
            .divided(by: .natural(2, usage: &admission), usage: &admission)
        let refined = try retained.refined(maximumWidth: width, maximumDepth: maximumDepth, usage: &admission)
        try RationalAlgebraStorage.retain(1, of: Self.self, usage: &admission)
        return Self(polynomial: polynomial,
            isolation: .init(lower: refined.isolation.lower, upper: refined.isolation.upper,
                excludesLower: refined.isolation.excludesLowerEndpoint,
                excludesUpper: refined.isolation.excludesUpperEndpoint,
                depth: refined.isolation.isolationDepth), admissionDomain: admissionDomain)
    }
}
