import CADCore

/// Original direct-sphere equation on one retained native rational curve span.
package struct OriginalSphereCurvePullback: Sendable {
    package let sphere: AnalyticSurface3D
    package let curve: OriginalRationalCurvePolynomial
    package let domain: OriginalRationalParameterDomain
    package let equation: ExactBivariatePolynomial
    package let denominator: ExactBivariatePolynomial

    package init<B: ExactScalarAdmission & ~Copyable>(sphere: AnalyticSurface3D,
        curve: OriginalRationalCurvePolynomial, tolerance: ModelingTolerance,
        usage: inout B) throws {
        try intersectionAlgebraStep(&usage)
        guard case .sphere(let center, let radius) = sphere else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                message: "An original sphere pullback requires a direct authored sphere.")
        }
        try sphere.validate(tolerance: tolerance, using: &usage)
        guard curve.homogeneous.count == 4 else {
            throw rationalAlgebraFailure("An original sphere pullback requires four homogeneous curve laws.")
        }
        for polynomial in curve.homogeneous {
            for term in try polynomial.orderedTerms(usage: &usage) {
                try intersectionAlgebraStep(&usage)
                guard term.key.v == 0 else {
                    throw rationalAlgebraFailure("An original sphere pullback requires one original curve parameter.")
                }
            }
        }
        let weight = curve.homogeneous[3]
        guard !weight.isZero else {
            throw rationalAlgebraFailure("An original sphere pullback cannot issue a zero denominator.")
        }
        var raw = ExactBivariatePolynomial.zero
        for axis in 0..<3 {
            try intersectionAlgebraStep(&usage)
            let coordinate = axis == 0 ? center.x : axis == 1 ? center.y : center.z
            let original = try ExactRationalCoefficient.originalDouble(coordinate, usage: &usage)
            let relative = try curve.homogeneous[axis].subtracting(
                weight.scaled(by: original, usage: &usage), usage: &usage)
            raw = try raw.adding(relative.multiplied(by: relative, usage: &usage), usage: &usage)
        }
        let originalRadius = try ExactRationalCoefficient.originalDouble(radius, usage: &usage)
        let radiusSquared = try originalRadius.multiplied(by: originalRadius, usage: &usage)
        raw = try raw.subtracting(weight.multiplied(by: weight, usage: &usage)
            .scaled(by: radiusSquared, usage: &usage), usage: &usage)
        let domain = try OriginalRationalParameterDomain(lower: curve.lowerParameter,
            upper: curve.upperParameter, usage: &usage)
        try RationalAlgebraStorage.retain(1, of: Self.self, usage: &usage)
        try CurrentTaskCancellationChecker().checkCancellation()
        self.sphere = sphere; self.curve = curve; self.domain = domain
        equation = raw; denominator = weight
    }

    /// Binds the raw original equation and denominator to the same source span.
    package func relation<B: ExactScalarAdmission & ~Copyable>(usage: inout B) throws -> OriginalPolynomialRelation {
        try intersectionAlgebraStep(&usage)
        let equation = try originalPolynomial(self.equation, usage: &usage)
        let denominator = try originalPolynomial(self.denominator, usage: &usage)
        try RationalAlgebraStorage.retain(2, of: OriginalRationalPolynomial.self, usage: &usage)
        try RationalAlgebraStorage.retain(4, of: OriginalPolynomialPredicate.Instruction.self, usage: &usage)
        let predicate = try OriginalPolynomialPredicate(polynomialCount: 2,
            instructions: [.sign(polynomial: 0, .zero), .sign(polynomial: 1, .zero), .not, .and],
            usage: &usage)
        try RationalAlgebraStorage.retain(1, of: OriginalRationalParameterDomain.self, usage: &usage)
        let relation = try OriginalPolynomialRelation(variableCount: 1, polynomials: [equation, denominator],
            predicate: predicate, domains: [domain], usage: &usage)
        try CurrentTaskCancellationChecker().checkCancellation()
        return relation
    }

    private func originalPolynomial<B: ExactScalarAdmission & ~Copyable>(_ source: ExactBivariatePolynomial,
        usage: inout B) throws -> OriginalRationalPolynomial {
        let ordered = try source.orderedTerms(usage: &usage)
        try RationalAlgebraStorage.retain(ordered.count, of: OriginalRationalPolynomial.Term.self, usage: &usage)
        var terms: [OriginalRationalPolynomial.Term] = []; terms.reserveCapacity(ordered.count)
        for term in ordered {
            try intersectionAlgebraStep(&usage)
            try RationalAlgebraStorage.retain(1, of: Int.self, usage: &usage)
            terms.append(.init(coefficient: term.value, powers: [term.key.u]))
        }
        return try .init(variableCount: 1, terms: terms, usage: &usage)
    }
}
