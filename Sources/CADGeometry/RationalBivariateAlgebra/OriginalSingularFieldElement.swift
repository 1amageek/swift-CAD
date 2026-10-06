/// Exact rational functions in one retained original real algebraic tower.
package struct OriginalSingularFieldElement: Sendable {
    enum Storage: Sendable {
        case original(ExactBivariatePolynomial, ExactBivariatePolynomial)
        case extended(OriginalSingularFieldPolynomial, OriginalSingularFieldPolynomial)
    }
    package let context: OriginalSingularFieldContext
    let storage: Storage
    init(context: OriginalSingularFieldContext, storage: Storage) { self.context = context; self.storage = storage }

    package static func constant<B: RationalAlgebraAdmitting>(_ value: ExactRationalCoefficient,
        in context: OriginalSingularFieldContext, maximumDepth: Int, usage: inout B) throws -> Self {
        switch context.source {
        case .rational, .original:
            return try Self(context: context, storage: .original(.constant(value, usage: &usage), .constant(.one, usage: &usage)))
        case .extended(let root):
            let coefficient = try Self.constant(value, in: root.polynomial.context, maximumDepth: maximumDepth, usage: &usage)
            return try coefficient.embedded(in: context, maximumDepth: maximumDepth, usage: &usage)
        }
    }

    package static func original<B: RationalAlgebraAdmitting>(_ polynomial: ExactBivariatePolynomial,
        in context: OriginalSingularFieldContext, usage: inout B) throws -> Self {
        guard case .original = context.source else { throw rationalAlgebraFailure("Original station polynomial needs its original field context.") }
        return try Self(context: context, storage: .original(polynomial, .constant(.one, usage: &usage)))
    }

    package func rationalValue<B: RationalAlgebraAdmitting>(usage: inout B) throws -> ExactRationalCoefficient? {
        switch storage {
        case .original(let n, let d):
            if n.uDegree > 0 || n.vDegree > 0 || d.uDegree > 0 || d.vDegree > 0 { return nil }
            return try n.evaluated(atU: .zero, v: .zero, usage: &usage)
                .divided(by: d.evaluated(atU: .zero, v: .zero, usage: &usage), usage: &usage)
        case .extended(let n, let d):
            if n.degree > 0 || d.degree > 0 { return nil }
            if n.isZero { return .zero }
            guard let a = n.coefficients.first, let b = d.coefficients.first,
                let first = try a.rationalValue(usage: &usage), let second = try b.rationalValue(usage: &usage) else { return nil }
            return try first.divided(by: second, usage: &usage)
        }
    }

    package func sign<B: RationalAlgebraAdmitting>(maximumDepth: Int, usage: inout B) throws -> ExactAlgebraicRealRoot.Sign {
        let numerator: ExactAlgebraicRealRoot.Sign, denominator: ExactAlgebraicRealRoot.Sign
        switch (context.source, storage) {
        case (.rational, .original(let n, let d)):
            guard n.uDegree <= 0, n.vDegree <= 0, d.uDegree <= 0, d.vDegree <= 0 else {
                throw rationalAlgebraFailure("Rational field coefficient retained a foreign variable.")
            }
            let a = try n.evaluated(atU: .zero, v: .zero, usage: &usage)
            let b = try d.evaluated(atU: .zero, v: .zero, usage: &usage)
            numerator = a.isPositive ? .positive : a.isNegative ? .negative : .zero
            denominator = b.isPositive ? .positive : b.isNegative ? .negative : .zero
        case (.original(let root), .original(let n, let d)):
            numerator = try root.sign(of: n, maximumDepth: maximumDepth, usage: &usage)
            denominator = try root.sign(of: d, maximumDepth: maximumDepth, usage: &usage)
        case (.extended(let root), .extended(let n, let d)):
            numerator = try root.sign(of: n, maximumDepth: maximumDepth, usage: &usage)
            denominator = try root.sign(of: d, maximumDepth: maximumDepth, usage: &usage)
        default: throw rationalAlgebraFailure("Original field value contradicts its retained context.")
        }
        if case .zero = denominator { throw rationalAlgebraFailure("Original singular field denominator vanishes.") }
        if case .zero = numerator { return .zero }
        switch (numerator, denominator) {
        case (.positive, .positive), (.negative, .negative): return .positive
        default: return .negative
        }
    }

    package func embedded<B: RationalAlgebraAdmitting>(in target: OriginalSingularFieldContext,
        maximumDepth: Int, usage: inout B) throws -> Self {
        if context === target { return self }
        guard let parent = target.parent else { throw rationalAlgebraFailure("Unrelated original field contexts cannot be implicitly identified.") }
        let value = try embedded(in: parent, maximumDepth: maximumDepth, usage: &usage)
        let one = try Self.constant(.one, in: parent, maximumDepth: maximumDepth, usage: &usage)
        try RationalAlgebraStorage.retain(2, of: Self.self, usage: &usage)
        return try Self(context: target, storage: .extended(
            OriginalSingularFieldPolynomial(context: parent, coefficients: [value], maximumDepth: maximumDepth, usage: &usage),
            OriginalSingularFieldPolynomial(context: parent, coefficients: [one], maximumDepth: maximumDepth, usage: &usage)))
    }

    package func adding<B: RationalAlgebraAdmitting>(_ other: Self, maximumDepth: Int, usage: inout B) throws -> Self {
        let b = try other.embedded(in: context, maximumDepth: maximumDepth, usage: &usage)
        switch (storage, b.storage) {
        case (.original(let a, let d), .original(let c, let e)):
            return try Self(context: context, storage: .original(a.multiplied(by: e, usage: &usage)
                .adding(c.multiplied(by: d, usage: &usage), usage: &usage), d.multiplied(by: e, usage: &usage)))
        case (.extended(let a, let d), .extended(let c, let e)):
            return try Self(context: context, storage: .extended(a.multiplied(by: e, maximumDepth: maximumDepth, usage: &usage)
                .adding(c.multiplied(by: d, maximumDepth: maximumDepth, usage: &usage), maximumDepth: maximumDepth, usage: &usage),
                d.multiplied(by: e, maximumDepth: maximumDepth, usage: &usage)))
        default: throw rationalAlgebraFailure("Original field sum has incompatible value storage.")
        }
    }

    package func negated<B: RationalAlgebraAdmitting>(maximumDepth: Int, usage: inout B) throws -> Self {
        switch storage {
        case .original(let n, let d): return try Self(context: context, storage: .original(n.scaled(by: .one.negated, usage: &usage), d))
        case .extended(let n, let d): return try Self(context: context, storage: .extended(n.negated(maximumDepth: maximumDepth, usage: &usage), d))
        }
    }
    package func subtracting<B: RationalAlgebraAdmitting>(_ other: Self, maximumDepth: Int, usage: inout B) throws -> Self {
        try adding(other.negated(maximumDepth: maximumDepth, usage: &usage), maximumDepth: maximumDepth, usage: &usage)
    }
    package func multiplied<B: RationalAlgebraAdmitting>(by other: Self, maximumDepth: Int, usage: inout B) throws -> Self {
        let b = try other.embedded(in: context, maximumDepth: maximumDepth, usage: &usage)
        switch (storage, b.storage) {
        case (.original(let a, let d), .original(let c, let e)):
            return try Self(context: context, storage: .original(a.multiplied(by: c, usage: &usage), d.multiplied(by: e, usage: &usage)))
        case (.extended(let a, let d), .extended(let c, let e)):
            return try Self(context: context, storage: .extended(a.multiplied(by: c, maximumDepth: maximumDepth, usage: &usage),
                d.multiplied(by: e, maximumDepth: maximumDepth, usage: &usage)))
        default: throw rationalAlgebraFailure("Original field product has incompatible value storage.")
        }
    }
    package func divided<B: RationalAlgebraAdmitting>(by other: Self, maximumDepth: Int, usage: inout B) throws -> Self {
        let b = try other.embedded(in: context, maximumDepth: maximumDepth, usage: &usage)
        if case .zero = try b.sign(maximumDepth: maximumDepth, usage: &usage) { throw rationalAlgebraFailure("Original field division by zero.") }
        switch (storage, b.storage) {
        case (.original(let a, let d), .original(let c, let e)):
            return try Self(context: context, storage: .original(a.multiplied(by: e, usage: &usage), d.multiplied(by: c, usage: &usage)))
        case (.extended(let a, let d), .extended(let c, let e)):
            return try Self(context: context, storage: .extended(a.multiplied(by: e, maximumDepth: maximumDepth, usage: &usage),
                d.multiplied(by: c, maximumDepth: maximumDepth, usage: &usage)))
        default: throw rationalAlgebraFailure("Original field quotient has incompatible value storage.")
        }
    }
}
