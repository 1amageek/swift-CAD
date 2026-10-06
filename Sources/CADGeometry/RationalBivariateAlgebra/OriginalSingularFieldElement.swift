import CADCore

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
            guard let a = try n.originalConstantCoefficient(usage: &usage),
                let b = try d.originalConstantCoefficient(usage: &usage) else { return nil }
            guard !b.isZero else { throw rationalAlgebraFailure("Original singular field denominator vanishes.") }
            try usage.consumeExactWork(1)
            if b == .one { return a }
            return try a.divided(by: b, usage: &usage)
        case .extended(let n, let d):
            if n.degree > 0 || d.degree > 0 { return nil }
            if n.isZero { return .zero }
            guard let a = n.coefficients.first, let b = d.coefficients.first,
                let first = try a.rationalValue(usage: &usage), let second = try b.rationalValue(usage: &usage) else { return nil }
            return try first.divided(by: second, usage: &usage)
        }
    }

    package func sign<B: RationalAlgebraAdmitting>(maximumDepth: Int, usage: inout B) throws -> ExactAlgebraicRealRoot.Sign {
        switch (context.source, storage) {
        case (.rational, .original), (.original, .original): break
        case (.extended(let root), .extended(let n, let d)):
            guard n.context === root.polynomial.context, d.context === root.polynomial.context else {
                throw rationalAlgebraFailure("Original field constant has an unrelated parent field.")
            }
        default: throw rationalAlgebraFailure("Original field value contradicts its retained context.")
        }
        if case .original(let n, let d) = storage,
            let a = try n.originalConstantCoefficient(usage: &usage),
            let b = try d.originalConstantCoefficient(usage: &usage) {
            guard !b.isZero else { throw rationalAlgebraFailure("Original singular field denominator vanishes.") }
            if a.isZero { return .zero }
            return a.isPositive == b.isPositive ? .positive : .negative
        }
        if let value = try rationalValue(usage: &usage) {
            return value.isPositive ? .positive : value.isNegative ? .negative : .zero
        }
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
        if let (a, c) = try originalConstants(with: b, usage: &usage) {
            return try .constant(a.adding(c, usage: &usage), in: context, maximumDepth: maximumDepth, usage: &usage)
        }
        switch (storage, b.storage) {
        case (.original(let a, let d), .original(let c, let e)):
            return try Self(context: context, storage: .original(a.multiplied(by: e, usage: &usage)
                .adding(c.multiplied(by: d, usage: &usage), usage: &usage), d.multiplied(by: e, usage: &usage)))
        case (.extended(let a, let d), .extended(let c, let e)):
            return try Self.reducedFraction(in: context, numerator: a.multiplied(by: e, maximumDepth: maximumDepth, usage: &usage)
                .adding(c.multiplied(by: d, maximumDepth: maximumDepth, usage: &usage), maximumDepth: maximumDepth, usage: &usage),
                denominator: d.multiplied(by: e, maximumDepth: maximumDepth, usage: &usage),
                maximumDepth: maximumDepth, usage: &usage)
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
        if let (a, c) = try originalConstants(with: b, usage: &usage) {
            return try .constant(a.multiplied(by: c, usage: &usage), in: context, maximumDepth: maximumDepth, usage: &usage)
        }
        switch (storage, b.storage) {
        case (.original(let a, let d), .original(let c, let e)):
            return try Self(context: context, storage: .original(a.multiplied(by: c, usage: &usage), d.multiplied(by: e, usage: &usage)))
        case (.extended(let a, let d), .extended(let c, let e)):
            return try Self.reducedFraction(in: context,
                numerator: a.multiplied(by: c, maximumDepth: maximumDepth, usage: &usage),
                denominator: d.multiplied(by: e, maximumDepth: maximumDepth, usage: &usage),
                maximumDepth: maximumDepth, usage: &usage)
        default: throw rationalAlgebraFailure("Original field product has incompatible value storage.")
        }
    }
    package func divided<B: RationalAlgebraAdmitting>(by other: Self, maximumDepth: Int, usage: inout B) throws -> Self {
        let b = try other.embedded(in: context, maximumDepth: maximumDepth, usage: &usage)
        if case .zero = try b.sign(maximumDepth: maximumDepth, usage: &usage) { throw rationalAlgebraFailure("Original field division by zero.") }
        if let (a, c) = try originalConstants(with: b, usage: &usage) {
            return try .constant(a.divided(by: c, usage: &usage), in: context, maximumDepth: maximumDepth, usage: &usage)
        }
        switch (storage, b.storage) {
        case (.original(let a, let d), .original(let c, let e)):
            return try Self(context: context, storage: .original(a.multiplied(by: e, usage: &usage), d.multiplied(by: c, usage: &usage)))
        case (.extended(let a, let d), .extended(let c, let e)):
            return try Self.reducedFraction(in: context,
                numerator: a.multiplied(by: e, maximumDepth: maximumDepth, usage: &usage),
                denominator: d.multiplied(by: c, maximumDepth: maximumDepth, usage: &usage),
                maximumDepth: maximumDepth, usage: &usage)
        default: throw rationalAlgebraFailure("Original field quotient has incompatible value storage.")
        }
    }

    /// Original constant laws remain exact and retain their immutable field owner.
    private func originalConstants<B: RationalAlgebraAdmitting>(with other: Self,
        usage: inout B) throws -> (ExactRationalCoefficient, ExactRationalCoefficient)? {
        try usage.consumeExactWork(1)
        try CurrentTaskCancellationChecker().checkCancellation()
        guard case .original = storage, case .original = other.storage else { return nil }
        switch context.source {
        case .rational, .original: break
        case .extended: throw rationalAlgebraFailure("Original constant storage contradicts its retained field context.")
        }
        guard other.context === context else { throw rationalAlgebraFailure("Original constants require the identical field owner.") }
        guard let a = try rationalValue(usage: &usage), let b = try other.rationalValue(usage: &usage) else { return nil }
        return (a, b)
    }

    /// Bounds symbolic degree without changing the selected original root.
    private static func reducedFraction<B: RationalAlgebraAdmitting>(in context: OriginalSingularFieldContext,
        numerator: OriginalSingularFieldPolynomial, denominator: OriginalSingularFieldPolynomial,
        maximumDepth: Int, usage: inout B) throws -> Self {
        guard case .extended(let root) = context.source,
              numerator.context === root.polynomial.context,
              denominator.context === root.polynomial.context else {
            throw rationalAlgebraFailure("Ordered-field reduction requires the retained root's original parent field.")
        }
        let n = numerator.degree >= root.polynomial.degree
            ? try numerator.divided(by: root.polynomial, maximumDepth: maximumDepth, usage: &usage).remainder
            : numerator
        let d = denominator.degree >= root.polynomial.degree
            ? try denominator.divided(by: root.polynomial, maximumDepth: maximumDepth, usage: &usage).remainder
            : denominator
        guard let leading = d.coefficients.last else {
            throw rationalAlgebraFailure("Ordered-field reduction exposes an original zero denominator.")
        }
        if try leading.rationalValue(usage: &usage) == .one {
            return Self(context: context, storage: .extended(n, d))
        }
        func normalized(_ polynomial: OriginalSingularFieldPolynomial, usage: inout B)
            throws -> OriginalSingularFieldPolynomial {
            try RationalAlgebraStorage.retain(polynomial.coefficients.count, of: Self.self, usage: &usage)
            var values: [Self] = []; values.reserveCapacity(polynomial.coefficients.count)
            for value in polynomial.coefficients {
                values.append(try value.divided(by: leading, maximumDepth: maximumDepth, usage: &usage))
            }
            return try .init(context: polynomial.context, coefficients: values,
                maximumDepth: maximumDepth, usage: &usage)
        }
        return try Self(context: context, storage: .extended(normalized(n, usage: &usage), normalized(d, usage: &usage)))
    }
}
