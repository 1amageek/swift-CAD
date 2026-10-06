/// Exact real-zero equivalence for same-sign sums of pure positive even powers.
package struct OriginalEvenPowerEquationZeroSet: Sendable {
    package struct Term: Sendable {
        package let power: ExactIntersectionPolynomial.Power
        package let coefficient: ExactRationalCoefficient
        package let coordinate: Int
        package let exponent: Int
    }

    package let equationIndex: Int
    package let guardedEquation: ExactIntersectionPolynomial
    package let coefficientSign: Int
    package let terms: [Term]
    package let coordinates: [Int]
    package let coordinateEquations: [ExactIntersectionPolynomial]
    package let reconstruction: ExactIntersectionPolynomial

    private init(equationIndex: Int, guardedEquation: ExactIntersectionPolynomial,
        coefficientSign: Int, terms: [Term], coordinates: [Int],
        coordinateEquations: [ExactIntersectionPolynomial], reconstruction: ExactIntersectionPolynomial) {
        self.equationIndex = equationIndex; self.guardedEquation = guardedEquation
        self.coefficientSign = coefficientSign; self.terms = terms; self.coordinates = coordinates
        self.coordinateEquations = coordinateEquations; self.reconstruction = reconstruction
    }

    package static func prepare<B: RationalAlgebraAdmitting>(_ equation: ExactIntersectionPolynomial,
        equationIndex: Int, usage: inout B) throws -> Self? {
        try intersectionAlgebraStep(&usage)
        if equation.isZero || equation.isConstant { return nil }
        let originalTerms = try equation.orderedTerms(usage: &usage)
        try RationalAlgebraStorage.retain(originalTerms.count, of: Term.self, usage: &usage)
        var terms: [Term] = []; terms.reserveCapacity(originalTerms.count)
        let coordinateCapacity = min(equation.variableCount, originalTerms.count)
        try RationalAlgebraStorage.retain(coordinateCapacity, of: Int.self, usage: &usage)
        var coordinates: [Int] = []; coordinates.reserveCapacity(coordinateCapacity)
        var coefficientSign = 0
        for originalTerm in originalTerms {
            try intersectionAlgebraStep(&usage)
            let sign = originalTerm.value.canonicalSign
            guard sign != 0, coefficientSign == 0 || coefficientSign == sign else { return nil }
            coefficientSign = sign
            var coordinate: Int?
            var exponent = 0
            for axis in 0..<equation.variableCount {
                try intersectionAlgebraStep(&usage)
                let power = try originalTerm.key.exponent(at: axis)
                if power == 0 { continue }
                guard coordinate == nil, power > 0, power % 2 == 0 else { return nil }
                coordinate = axis; exponent = power
            }
            guard let coordinate else { return nil }
            terms.append(.init(power: originalTerm.key, coefficient: originalTerm.value,
                coordinate: coordinate, exponent: exponent))
            var alreadyRetained = false
            for retained in coordinates {
                try intersectionAlgebraStep(&usage)
                if retained == coordinate { alreadyRetained = true; break }
            }
            if !alreadyRetained { coordinates.append(coordinate) }
        }
        try RationalAlgebraStorage.retain(coordinates.count, of: ExactIntersectionPolynomial.self, usage: &usage)
        var coordinateEquations: [ExactIntersectionPolynomial] = []
        coordinateEquations.reserveCapacity(coordinates.count)
        for coordinate in coordinates {
            try intersectionAlgebraStep(&usage)
            coordinateEquations.append(try .coordinate(variableCount: equation.variableCount,
                at: coordinate, usage: &usage))
        }
        var reconstruction = try ExactIntersectionPolynomial.zero(variableCount: equation.variableCount)
        for term in terms {
            try intersectionAlgebraStep(&usage)
            let monomial = try ExactIntersectionPolynomial.monomial(variableCount: equation.variableCount,
                power: term.power, coefficient: term.coefficient, usage: &usage)
            reconstruction = try reconstruction.adding(monomial, usage: &usage)
        }
        guard try reconstruction.matches(equation, usage: &usage) else {
            throw rationalAlgebraFailure("Pure even-power real-zero proof lost its exact guarded equation reconstruction.")
        }
        // Multiplying by coefficientSign makes every coefficient strictly positive.
        // Each pure even power is nonnegative over the reals, with zero precisely
        // at its coordinate's zero. A zero sum therefore forces all retained
        // coordinate equations to vanish; their simultaneous zero also zeros
        // every reconstructed term. This does not assert rational ideal equality.
        try RationalAlgebraStorage.retain(1, of: Self.self, usage: &usage)
        try Task.checkCancellation()
        return .init(equationIndex: equationIndex, guardedEquation: equation,
            coefficientSign: coefficientSign, terms: terms, coordinates: coordinates,
            coordinateEquations: coordinateEquations, reconstruction: reconstruction)
    }
}
