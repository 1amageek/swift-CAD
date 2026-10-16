import CADCore

/// Exact spatial derivative numerators sharing the original positive weight law.
package struct OriginalRationalCurveDerivativeLaw: Sendable {
    package let original: OriginalRationalCurvePolynomial
    /// Order-major XYZ derivative numerators. Entry n has denominator W^(n+1).
    package let numerators: [[ExactBivariatePolynomial]]
    package let denominators: [ExactBivariatePolynomial]

    package init<B: ExactScalarAdmission & ~Copyable>(original: OriginalRationalCurvePolynomial,
        throughOrder: Int, usage: inout B) throws {
        guard throughOrder >= 0 else {
            throw rationalAlgebraFailure("Original rational curve derivative order must be nonnegative.")
        }
        let count = try rationalAlgebraCount(throughOrder, 1)
        try RationalAlgebraStorage.retain(count, of: [ExactBivariatePolynomial].self, usage: &usage)
        try RationalAlgebraStorage.retain(count, of: ExactBivariatePolynomial.self, usage: &usage)
        try RationalAlgebraStorage.retain(3, of: ExactBivariatePolynomial.self, usage: &usage)
        self.original = original
        let weight = original.homogeneous[3]
        let weightDerivative = try weight.differentiated(alongU: true, usage: &usage)
        var rows: [[ExactBivariatePolynomial]] = []; rows.reserveCapacity(count)
        rows.append(Array(original.homogeneous[0..<3]))
        var powers: [ExactBivariatePolynomial] = []; powers.reserveCapacity(count)
        powers.append(weight)
        if throughOrder > 0 {
            for order in 1...throughOrder {
                try CurrentTaskCancellationChecker().checkCancellation()
                let factor = try ExactRationalCoefficient.natural(order, usage: &usage)
                let scaledWeightDerivative = try weightDerivative.scaled(by: factor, usage: &usage)
                try RationalAlgebraStorage.retain(3, of: ExactBivariatePolynomial.self, usage: &usage)
                var row: [ExactBivariatePolynomial] = []; row.reserveCapacity(3)
                for axis in 0..<3 {
                    let prior = rows[order - 1][axis]
                    row.append(try prior.differentiated(alongU: true, usage: &usage)
                        .multiplied(by: weight, usage: &usage)
                        .subtracting(prior.multiplied(by: scaledWeightDerivative, usage: &usage), usage: &usage))
                }
                rows.append(row)
                powers.append(try powers[order - 1].multiplied(by: weight, usage: &usage))
            }
        }
        numerators = rows; denominators = powers
    }

    /// Exact difference numerators in the same original parameter chart.
    package func equalityNumerators<B: ExactScalarAdmission & ~Copyable>(with other: Self,
        order: Int, usage: inout B) throws -> [ExactBivariatePolynomial] {
        guard order >= 0, order < numerators.count, order < other.numerators.count else {
            throw rationalAlgebraFailure("Original derivative equality requires an admitted derivative order.")
        }
        try RationalAlgebraStorage.retain(3, of: ExactBivariatePolynomial.self, usage: &usage)
        var result: [ExactBivariatePolynomial] = []; result.reserveCapacity(3)
        for axis in 0..<3 {
            result.append(try numerators[order][axis].multiplied(by: other.denominators[order], usage: &usage)
                .subtracting(other.numerators[order][axis].multiplied(by: denominators[order], usage: &usage), usage: &usage))
        }
        return result
    }
}
