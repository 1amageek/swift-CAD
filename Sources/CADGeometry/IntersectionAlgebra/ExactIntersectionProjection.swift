import CADCore

/// Full rational projection preparation; does not publish real cells or intersections.
package struct ExactIntersectionProjection: Sendable {
    private typealias Polynomial = ExactIntersectionPolynomial
    package let axis: Int
    package let sources: [ExactIntersectionPolynomial]
    package let polynomials: [ExactIntersectionPolynomial]

    private init(axis: Int, sources: [ExactIntersectionPolynomial], polynomials: [ExactIntersectionPolynomial]) {
        self.axis = axis; self.sources = sources; self.polynomials = polynomials
    }

    package static func prepare<B: RationalAlgebraAdmitting>(
        sources: [ExactIntersectionPolynomial], variableCount: Int, axis: Int,
        usage: inout B) throws -> Self {
        guard (1...ExactIntersectionPolynomial.maximumVariableCount).contains(variableCount), axis >= 0, axis < variableCount else {
            throw rationalAlgebraFailure("Projection requires a bound axis and one original polynomial ring.")
        }
        for source in sources {
            try intersectionAlgebraStep(&usage)
            guard source.variableCount == variableCount else {
                throw rationalAlgebraFailure("Projection sources do not share one original polynomial ring.")
            }
        }
        // Projection is a set operation; retain original truth sources separately.
        var active: [Polynomial] = []
        for source in sources { try insert(source, into: &active, usage: &usage) }
        try splitCommonFactors(&active, usage: &usage)
        try RationalAlgebraStorage.retain(active.count, of: [Polynomial].self, usage: &usage)
        var families: [[Polynomial]] = []
        var projected: [Polynomial] = []
        let coordinate = try Polynomial.coordinate(variableCount: variableCount, at: axis, usage: &usage)
        for source in active {
            try intersectionAlgebraStep(&usage)
            let coefficients = try source.axisCoefficients(at: axis, usage: &usage)
            var reducta: [Polynomial] = []
            var remainder = source
            var degree = coefficients.count - 1
            while degree >= 0 {
                try intersectionAlgebraStep(&usage)
                if coefficients[degree].isZero { degree -= 1; continue }
                if degree == 0 {
                    try insert(remainder, into: &projected, usage: &usage)
                    break
                }
                try RationalAlgebraStorage.retain(1, of: Polynomial.self, usage: &usage)
                reducta.append(remainder)
                try insert(coefficients[degree], into: &projected, usage: &usage)
                let derivative = try remainder.differentiated(at: axis, usage: &usage)
                for coefficient in try ExactIntersectionSubresultants.principal(
                    remainder, derivative, axis: axis, usage: &usage) {
                    try insert(coefficient, into: &projected, usage: &usage)
                }
                var leadingTerm = coefficients[degree]
                for _ in 0..<degree {
                    leadingTerm = try leadingTerm.multiplied(by: coordinate, usage: &usage)
                }
                remainder = try remainder.subtracting(leadingTerm, usage: &usage)
                degree -= 1
            }
            families.append(reducta)
        }
        for first in families.indices {
            for second in (first + 1)..<families.count {
                try intersectionAlgebraStep(&usage)
                for a in families[first] {
                    for b in families[second] {
                        for coefficient in try ExactIntersectionSubresultants.principal(
                            a, b, axis: axis, usage: &usage) {
                            try insert(coefficient, into: &projected, usage: &usage)
                        }
                    }
                }
            }
        }
        return Self(axis: axis, sources: sources, polynomials: projected)
    }

    private static func insert<B: RationalAlgebraAdmitting>(_ polynomial: Polynomial,
        into result: inout [Polynomial], usage: inout B) throws {
        try intersectionAlgebraStep(&usage)
        if polynomial.isZero || polynomial.isConstant { return }
        let normalized = try ExactIntersectionPolynomialGCD.squareFree(polynomial, usage: &usage)
        for existing in result {
            if try existing.matches(normalized, usage: &usage) { return }
        }
        try RationalAlgebraStorage.retain(1, of: Polynomial.self, usage: &usage)
        result.append(normalized)
    }

    private static func splitCommonFactors<B: RationalAlgebraAdmitting>(_ basis: inout [Polynomial],
        usage: inout B) throws {
        var changed = true
        while changed {
            changed = false
            outer: for first in basis.indices {
                for second in (first + 1)..<basis.count {
                    try intersectionAlgebraStep(&usage)
                    let common = try ExactIntersectionPolynomialGCD.gcd(basis[first], basis[second], usage: &usage)
                    if common.isConstant { continue }
                    let a = try basis[first].dividedExactly(by: common, usage: &usage)
                    let b = try basis[second].dividedExactly(by: common, usage: &usage)
                    basis[first] = common
                    try usage.consumeExactWork(basis.count - second)
                    basis.remove(at: second)
                    try insert(a, into: &basis, usage: &usage)
                    try insert(b, into: &basis, usage: &usage)
                    changed = true
                    break outer
                }
            }
        }
    }
}
