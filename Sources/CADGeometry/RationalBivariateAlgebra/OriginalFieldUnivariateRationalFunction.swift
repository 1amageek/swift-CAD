/// Exact original one-parameter rational expression over an immutable field owner.
package struct OriginalFieldUnivariateRationalFunction: Sendable {
    package let numerator: OriginalSingularFieldPolynomial
    package let denominator: OriginalSingularFieldPolynomial
    package var context: OriginalSingularFieldContext { numerator.context }

    package init<B: RationalAlgebraAdmitting>(numerator: OriginalSingularFieldPolynomial,
        denominator: OriginalSingularFieldPolynomial, maximumDepth: Int, usage: inout B) throws {
        guard numerator.context === denominator.context, !denominator.isZero else {
            throw rationalAlgebraFailure("Original rational function requires one field and a nonzero denominator law.")
        }
        let common = try OriginalSingularFieldPolynomial.gcd(numerator, denominator,
            maximumDepth: maximumDepth, usage: &usage)
        let first = try numerator.divided(by: common, maximumDepth: maximumDepth, usage: &usage)
        let second = try denominator.divided(by: common, maximumDepth: maximumDepth, usage: &usage)
        guard first.remainder.isZero, second.remainder.isZero else {
            throw rationalAlgebraFailure("Original rational expression cancellation left a nonzero remainder.")
        }
        self.numerator = first.quotient; self.denominator = second.quotient
    }

    package static func constant<B: RationalAlgebraAdmitting>(_ value: OriginalSingularFieldElement,
        maximumDepth: Int, usage: inout B) throws -> Self {
        let one = try OriginalSingularFieldElement.constant(.one, in: value.context, maximumDepth: maximumDepth, usage: &usage)
        try RationalAlgebraStorage.retain(2, of: OriginalSingularFieldElement.self, usage: &usage)
        return try .init(numerator: .init(context: value.context, coefficients: [value], maximumDepth: maximumDepth, usage: &usage),
            denominator: .init(context: value.context, coefficients: [one], maximumDepth: maximumDepth, usage: &usage),
            maximumDepth: maximumDepth, usage: &usage)
    }
    package func adding<B: RationalAlgebraAdmitting>(_ other: Self,
        maximumDepth: Int, usage: inout B) throws -> Self {
        try .init(numerator: numerator.multiplied(by: other.denominator, maximumDepth: maximumDepth, usage: &usage)
            .adding(other.numerator.multiplied(by: denominator, maximumDepth: maximumDepth, usage: &usage), maximumDepth: maximumDepth, usage: &usage),
            denominator: denominator.multiplied(by: other.denominator, maximumDepth: maximumDepth, usage: &usage),
            maximumDepth: maximumDepth, usage: &usage)
    }
    package func negated<B: RationalAlgebraAdmitting>(maximumDepth: Int, usage: inout B) throws -> Self {
        try .init(numerator: numerator.negated(maximumDepth: maximumDepth, usage: &usage), denominator: denominator,
            maximumDepth: maximumDepth, usage: &usage)
    }
    package func subtracting<B: RationalAlgebraAdmitting>(_ other: Self,
        maximumDepth: Int, usage: inout B) throws -> Self {
        try adding(other.negated(maximumDepth: maximumDepth, usage: &usage), maximumDepth: maximumDepth, usage: &usage)
    }
    package func multiplied<B: RationalAlgebraAdmitting>(by other: Self,
        maximumDepth: Int, usage: inout B) throws -> Self {
        try .init(numerator: numerator.multiplied(by: other.numerator, maximumDepth: maximumDepth, usage: &usage),
            denominator: denominator.multiplied(by: other.denominator, maximumDepth: maximumDepth, usage: &usage), maximumDepth: maximumDepth, usage: &usage)
    }
    package func divided<B: RationalAlgebraAdmitting>(by other: Self,
        maximumDepth: Int, usage: inout B) throws -> Self {
        try .init(numerator: numerator.multiplied(by: other.denominator, maximumDepth: maximumDepth, usage: &usage),
            denominator: denominator.multiplied(by: other.numerator, maximumDepth: maximumDepth, usage: &usage), maximumDepth: maximumDepth, usage: &usage)
    }
    package func power<B: RationalAlgebraAdmitting>(_ count: Int,
        maximumDepth: Int, usage: inout B) throws -> Self {
        guard count >= 0 else { throw rationalAlgebraFailure("Original rational power must be nonnegative.") }
        var result = try Self.constant(.constant(.one, in: context, maximumDepth: maximumDepth, usage: &usage),
            maximumDepth: maximumDepth, usage: &usage)
        for _ in 0..<count { result = try result.multiplied(by: self, maximumDepth: maximumDepth, usage: &usage) }
        return result
    }
    package func evaluated<B: RationalAlgebraAdmitting>(at parameter: OriginalSingularFieldElement,
        maximumDepth: Int, usage: inout B) throws -> OriginalSingularFieldElement {
        try numerator.evaluated(at: parameter, maximumDepth: maximumDepth, usage: &usage)
            .divided(by: denominator.evaluated(at: parameter, maximumDepth: maximumDepth, usage: &usage), maximumDepth: maximumDepth, usage: &usage)
    }
    package static func composed<B: RationalAlgebraAdmitting>(_ source: OriginalSingularFieldPlanePolynomial,
        withU u: Self, v: Self, maximumDepth: Int, usage: inout B) throws -> Self {
        guard source.context === u.context, source.context === v.context else {
            throw rationalAlgebraFailure("Original rational composition has unrelated coefficient owners.")
        }
        var result = try Self.constant(.constant(.zero, in: source.context, maximumDepth: maximumDepth, usage: &usage),
            maximumDepth: maximumDepth, usage: &usage)
        for (power, value) in try source.orderedTerms(usage: &usage) {
            let term = try u.power(power.u, maximumDepth: maximumDepth, usage: &usage)
                .multiplied(by: v.power(power.v, maximumDepth: maximumDepth, usage: &usage), maximumDepth: maximumDepth, usage: &usage)
                .multiplied(by: .constant(value, maximumDepth: maximumDepth, usage: &usage), maximumDepth: maximumDepth, usage: &usage)
            result = try result.adding(term, maximumDepth: maximumDepth, usage: &usage)
        }
        return result
    }
}
