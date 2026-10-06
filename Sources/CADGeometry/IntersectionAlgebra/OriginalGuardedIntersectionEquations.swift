import CADCore

/// Exact equation equivalence restricted to the retained nonzero denominator guards.
package struct OriginalGuardedIntersectionEquations: Sendable {
    package struct Division: Sendable {
        package let equationIndex: Int
        package let dividend: ExactIntersectionPolynomial
        package let factor: ExactIntersectionPolynomial
        package let quotient: ExactIntersectionPolynomial
        package let guardQuotient: ExactIntersectionPolynomial
    }

    package struct SupportDivision: Sendable {
        package let dividend: ExactIntersectionPolynomial
        package let factor: ExactIntersectionPolynomial
        package let quotient: ExactIntersectionPolynomial
        package let supportQuotient: ExactIntersectionPolynomial
        package let dividendDegree: Int
        package let quotientDegree: Int
    }

    package struct ZeroSetEquivalence: Sendable {
        package let equationIndex: Int
        package let guardedEquation: ExactIntersectionPolynomial
        package let support: ExactIntersectionPolynomial
        package let originalQuotient: ExactIntersectionPolynomial
        package let divisions: [SupportDivision]
        package let terminalCofactor: ExactIntersectionPolynomial
    }

    package let originalEquations: [ExactIntersectionPolynomial]
    package let denominatorGuards: [ExactIntersectionPolynomial]
    package let guardProduct: ExactIntersectionPolynomial
    package let normalizedEquations: [ExactIntersectionPolynomial]
    package let divisions: [Division]
    package let zeroSetEquivalences: [ZeroSetEquivalence]
    package let evenPowerZeroSets: [OriginalEvenPowerEquationZeroSet]

    package static func prepare<B: RationalAlgebraAdmitting>(equations: [ExactIntersectionPolynomial],
        denominatorGuards: [ExactIntersectionPolynomial], variableCount: Int,
        squareFreeRepeatedFactors: Bool = false, reducePureEvenPowerZeroSets: Bool = false,
        usage: inout B) throws -> Self {
        try intersectionAlgebraStep(&usage)
        var product = try ExactIntersectionPolynomial.constant(variableCount: variableCount, value: .one, usage: &usage)
        for guardPolynomial in denominatorGuards {
            guard !guardPolynomial.isZero else {
                throw rationalAlgebraFailure("Guarded equation normalization requires nonzero original denominator polynomials.")
            }
            product = try product.multiplied(by: guardPolynomial, usage: &usage)
        }
        try RationalAlgebraStorage.retain(equations.count, of: ExactIntersectionPolynomial.self, usage: &usage)
        var normalized: [ExactIntersectionPolynomial] = []; normalized.reserveCapacity(equations.count)
        var normalizedCapacity = equations.count
        var divisions: [Division] = []
        var equivalences: [ZeroSetEquivalence] = []
        var evenPowerZeroSets: [OriginalEvenPowerEquationZeroSet] = []
        var evenPowerZeroSetCapacity = 0
        for (index, equation) in equations.enumerated() {
            try intersectionAlgebraStep(&usage)
            guard equation.variableCount == variableCount else {
                throw rationalAlgebraFailure("Guarded equations must retain the original parameter ring.")
            }
            var current = equation
            // A zero equation is already equivalent everywhere; dividing it by
            // the guard repeatedly would not decrease any polynomial degree.
            while !current.isZero {
                let factor = try ExactIntersectionPolynomialGCD.gcd(current, product, usage: &usage)
                if factor.isConstant { break }
                let quotient = try current.dividedExactly(by: factor, usage: &usage)
                let guardQuotient = try product.dividedExactly(by: factor, usage: &usage)
                // Both retained identities are checked in the original ring.
                guard try factor.multiplied(by: quotient, usage: &usage).matches(current, usage: &usage),
                    try factor.multiplied(by: guardQuotient, usage: &usage).matches(product, usage: &usage) else {
                    throw rationalAlgebraFailure("Guarded normalization lost an exact original division identity.")
                }
                try RationalAlgebraStorage.retain(1, of: Division.self, usage: &usage)
                divisions.append(.init(equationIndex: index, dividend: current, factor: factor,
                    quotient: quotient, guardQuotient: guardQuotient))
                current = quotient
            }
            if reducePureEvenPowerZeroSets, let proof = try OriginalEvenPowerEquationZeroSet.prepare(current,
                equationIndex: index, usage: &usage) {
                try appendAdmitted(proof, to: &evenPowerZeroSets,
                    capacity: &evenPowerZeroSetCapacity, usage: &usage)
                for coordinateEquation in proof.coordinateEquations {
                    try intersectionAlgebraStep(&usage)
                    try appendAdmitted(coordinateEquation, to: &normalized,
                        capacity: &normalizedCapacity, usage: &usage)
                }
            } else if squareFreeRepeatedFactors, let equivalence = try squareFreeEquivalence(current,
                equationIndex: index, usage: &usage) {
                try RationalAlgebraStorage.retain(1, of: ZeroSetEquivalence.self, usage: &usage)
                equivalences.append(equivalence)
                try appendAdmitted(equivalence.support, to: &normalized,
                    capacity: &normalizedCapacity, usage: &usage)
            } else {
                try appendAdmitted(current, to: &normalized, capacity: &normalizedCapacity, usage: &usage)
            }
        }
        try RationalAlgebraStorage.retain(1, of: Self.self, usage: &usage)
        try CurrentTaskCancellationChecker().checkCancellation()
        return Self(originalEquations: equations, denominatorGuards: denominatorGuards,
            guardProduct: product, normalizedEquations: normalized, divisions: divisions,
            zeroSetEquivalences: equivalences, evenPowerZeroSets: evenPowerZeroSets)
    }

    private static func appendAdmitted<Element, B: RationalAlgebraAdmitting>(_ element: Element,
        to values: inout [Element], capacity: inout Int, usage: inout B) throws {
        if values.count == capacity {
            try intersectionAlgebraStep(&usage)
            let required = try rationalAlgebraCount(values.count, 1)
            let grown = capacity == 0 ? 1 : try rationalAlgebraCount(capacity, 2, multiply: true)
            let nextCapacity = max(required, grown)
            // The caller ledger is cumulative: a replacement allocation admits
            // its entire new buffer while the previous allocation stays charged.
            try RationalAlgebraStorage.retain(nextCapacity, of: Element.self, usage: &usage)
            values.reserveCapacity(nextCapacity)
            capacity = nextCapacity
        }
        values.append(element)
    }

    private static func squareFreeEquivalence<B: RationalAlgebraAdmitting>(_ equation: ExactIntersectionPolynomial,
        equationIndex: Int, usage: inout B) throws -> ZeroSetEquivalence? {
        try intersectionAlgebraStep(&usage)
        if equation.isZero || equation.isConstant { return nil }
        let support = try ExactIntersectionPolynomialGCD.squareFree(equation, usage: &usage)
        guard !support.isZero, !support.isConstant else {
            throw rationalAlgebraFailure("A nonconstant original equation lost its nonconstant square-free support.")
        }
        let originalQuotient = try equation.dividedExactly(by: support, usage: &usage)
        guard try support.multiplied(by: originalQuotient, usage: &usage).matches(equation, usage: &usage) else {
            throw rationalAlgebraFailure("Original square-free support lost its exact divisor identity.")
        }
        // Change only equations with genuine multiplicity, retaining all raw
        // equations for original differential rank and source correspondence.
        if originalQuotient.isConstant { return nil }
        var current = equation
        var divisions: [SupportDivision] = []
        while !current.isConstant {
            let degree = try totalDegree(current, usage: &usage)
            let factor = try ExactIntersectionPolynomialGCD.gcd(current, support, usage: &usage)
            guard !factor.isZero, !factor.isConstant else {
                throw rationalAlgebraFailure("Original zero-set proof cannot remove a constant support factor.")
            }
            let quotient = try current.dividedExactly(by: factor, usage: &usage)
            let supportQuotient = try support.dividedExactly(by: factor, usage: &usage)
            let quotientDegree = try totalDegree(quotient, usage: &usage)
            guard !quotient.isZero, quotientDegree < degree,
                try factor.multiplied(by: quotient, usage: &usage).matches(current, usage: &usage),
                try factor.multiplied(by: supportQuotient, usage: &usage).matches(support, usage: &usage) else {
                throw rationalAlgebraFailure("Original zero-set proof lost exact identity or strict degree descent.")
            }
            try RationalAlgebraStorage.retain(1, of: SupportDivision.self, usage: &usage)
            divisions.append(.init(dividend: current, factor: factor, quotient: quotient,
                supportQuotient: supportQuotient, dividendDegree: degree, quotientDegree: quotientDegree))
            current = quotient
        }
        guard !current.isZero else {
            throw rationalAlgebraFailure("Original zero-set proof requires a nonzero terminal cofactor.")
        }
        return .init(equationIndex: equationIndex, guardedEquation: equation, support: support,
            originalQuotient: originalQuotient, divisions: divisions, terminalCofactor: current)
    }

    private static func totalDegree<B: RationalAlgebraAdmitting>(_ polynomial: ExactIntersectionPolynomial,
        usage: inout B) throws -> Int {
        var result = 0
        for term in try polynomial.orderedTerms(usage: &usage) {
            var degree = 0
            for axis in 0..<polynomial.variableCount {
                try intersectionAlgebraStep(&usage)
                degree = try rationalAlgebraCount(degree, term.key.exponent(at: axis))
            }
            result = max(result, degree)
        }
        return result
    }
}
