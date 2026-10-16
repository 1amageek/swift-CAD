import CADCore

/// Exact complex-ideal classification, deliberately distinct from real component coverage.
package struct ExactIntersectionIdeal: Sendable {
    package enum Classification: Equatable, Sendable {
        case inconsistent
        case zeroDimensional
        case positiveDimensional
    }

    package let variableCount: Int
    package let originalEquations: [ExactIntersectionPolynomial]
    package let reducedBasis: [ExactIntersectionPolynomial]
    package let classification: Classification

    private init(variableCount: Int, originalEquations: [ExactIntersectionPolynomial],
        reducedBasis: [ExactIntersectionPolynomial], classification: Classification) {
        self.variableCount = variableCount
        self.originalEquations = originalEquations
        self.reducedBasis = reducedBasis
        self.classification = classification
    }

    package static func prepare<B: ExactScalarAdmission & ~Copyable>(
        equations: [ExactIntersectionPolynomial], variableCount: Int, usage: inout B) throws -> Self {
        try intersectionAlgebraStep(&usage)
        _ = try ExactIntersectionPolynomial.zero(variableCount: variableCount)
        for equation in equations {
            try intersectionAlgebraStep(&usage)
            guard equation.variableCount == variableCount else {
                throw rationalAlgebraFailure("Original ideal generators must share one parameter ring.")
            }
        }
        let basis = try ExactIntersectionGroebnerBasis.reducedBasis(equations,
            variableCount: variableCount, usage: &usage)
        let classification: Classification
        if basis.count == 1, !basis[0].isZero, basis[0].isConstant { classification = .inconsistent }
        else {
            var hasEveryPurePower = true
            for coordinate in 0..<variableCount {
                var hasPurePower = false
                for polynomial in basis {
                    try intersectionAlgebraStep(&usage)
                    guard let lead = try polynomial.leading(usage: &usage),
                          try lead.power.exponent(at: coordinate) > 0 else { continue }
                    var pure = true
                    for other in 0..<variableCount where other != coordinate {
                        if try lead.power.exponent(at: other) != 0 { pure = false; break }
                    }
                    if pure { hasPurePower = true; break }
                }
                if !hasPurePower { hasEveryPurePower = false; break }
            }
            classification = hasEveryPurePower ? .zeroDimensional : .positiveDimensional
        }
        return Self(variableCount: variableCount, originalEquations: equations,
                    reducedBasis: basis, classification: classification)
    }
}
