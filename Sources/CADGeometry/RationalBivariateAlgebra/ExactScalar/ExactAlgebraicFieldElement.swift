/// An exact rational function evaluated at one separately certified algebraic root.
struct ExactAlgebraicFieldElement: Sendable {
    let numerator: ExactBivariatePolynomial
    let denominator: ExactBivariatePolynomial
    init<B: RationalAlgebraAdmitting>(polynomial: ExactBivariatePolynomial, usage: inout B) throws {
        guard polynomial.vDegree <= 0 else { throw exactScalarBackendFailure("Algebraic field coefficient must belong to Q[u].") }
        numerator = polynomial; denominator = try .constant(.one, usage: &usage)
    }
    private init(numerator: ExactBivariatePolynomial, denominator: ExactBivariatePolynomial) {
        self.numerator = numerator; self.denominator = denominator
    }
    func sign<B: RationalAlgebraAdmitting>(at root: ExactAlgebraicRealRoot,
        maximumDepth: Int, usage: inout B) throws -> ExactAlgebraicRealRoot.Sign {
        let n = try root.sign(of: numerator, maximumDepth: maximumDepth, usage: &usage)
        if case .zero = n { return .zero }
        let d = try root.sign(of: denominator, maximumDepth: maximumDepth, usage: &usage)
        if case .zero = d { throw exactScalarBackendFailure("Exact algebraic coefficient denominator vanishes at its source root.") }
        switch (n, d) {
        case (.negative, .negative), (.positive, .positive): return .positive
        default: return .negative
        }
    }
    func adding<B: RationalAlgebraAdmitting>(_ other: Self, usage: inout B) throws -> Self {
        try Self(numerator: numerator.multiplied(by: other.denominator, usage: &usage)
            .adding(other.numerator.multiplied(by: denominator, usage: &usage), usage: &usage),
            denominator: denominator.multiplied(by: other.denominator, usage: &usage))
    }
    func negated<B: RationalAlgebraAdmitting>(usage: inout B) throws -> Self {
        try Self(numerator: numerator.scaled(by: .one.negated, usage: &usage), denominator: denominator)
    }
    func subtracting<B: RationalAlgebraAdmitting>(_ other: Self, usage: inout B) throws -> Self {
        try adding(other.negated(usage: &usage), usage: &usage)
    }
    func multiplied<B: RationalAlgebraAdmitting>(by other: Self, usage: inout B) throws -> Self {
        try Self(numerator: numerator.multiplied(by: other.numerator, usage: &usage),
            denominator: denominator.multiplied(by: other.denominator, usage: &usage))
    }
    func divided<B: RationalAlgebraAdmitting>(by other: Self, at root: ExactAlgebraicRealRoot,
        maximumDepth: Int, usage: inout B) throws -> Self {
        if case .zero = try other.sign(at: root, maximumDepth: maximumDepth, usage: &usage) {
            throw exactScalarBackendFailure("Exact algebraic field division by a zero source value.")
        }
        return try Self(numerator: numerator.multiplied(by: other.denominator, usage: &usage),
            denominator: denominator.multiplied(by: other.numerator, usage: &usage))
    }
}
