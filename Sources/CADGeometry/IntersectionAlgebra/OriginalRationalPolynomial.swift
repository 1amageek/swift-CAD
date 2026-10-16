import CADCore

/// An immutable polynomial over original rational coefficients.
public struct OriginalRationalPolynomial: Sendable {
    public struct Term: Sendable {
        public let coefficient: ExactRationalCoefficient
        public let powers: [Int]
        public init(coefficient: ExactRationalCoefficient, powers: [Int]) {
            self.coefficient = coefficient; self.powers = powers
        }
    }
    package let original: ExactIntersectionPolynomial
    public var variableCount: Int { original.variableCount }
    private init(_ original: ExactIntersectionPolynomial) { self.original = original }

    public init<B: ExactScalarAdmission & ~Copyable>(variableCount: Int, terms: [Term], usage: inout B) throws {
        try intersectionAlgebraStep(&usage)
        guard (1...4).contains(variableCount) else {
            throw rationalAlgebraFailure("The original rational relation port requires one through four coordinates.")
        }
        var polynomial = try ExactIntersectionPolynomial.zero(variableCount: variableCount)
        for term in terms {
            try intersectionAlgebraStep(&usage)
            guard term.powers.count == variableCount else {
                throw rationalAlgebraFailure("A polynomial term must bind every original coordinate.")
            }
            func power(_ axis: Int) -> Int { axis < variableCount ? term.powers[axis] : 0 }
            let monomial = try ExactIntersectionPolynomial.monomial(variableCount: variableCount,
                powers: (power(0), power(1), power(2), power(3), 0, 0, 0, 0, 0),
                coefficient: term.coefficient, usage: &usage)
            polynomial = try polynomial.adding(monomial, usage: &usage)
        }
        original = polynomial
    }

    public static func coordinate<B: ExactScalarAdmission & ~Copyable>(variableCount: Int,
        at axis: Int, usage: inout B) throws -> Self {
        guard (1...4).contains(variableCount) else {
            throw rationalAlgebraFailure("The original rational relation port requires one through four coordinates.")
        }
        return try Self(.coordinate(variableCount: variableCount, at: axis, usage: &usage))
    }

    public static func constant<B: ExactScalarAdmission & ~Copyable>(variableCount: Int,
        value: ExactRationalCoefficient, usage: inout B) throws -> Self {
        guard (1...4).contains(variableCount) else {
            throw rationalAlgebraFailure("The original rational relation port requires one through four coordinates.")
        }
        return try Self(.constant(variableCount: variableCount, value: value, usage: &usage))
    }

    public func adding<B: ExactScalarAdmission & ~Copyable>(_ other: Self, usage: inout B) throws -> Self {
        try Self(original.adding(other.original, usage: &usage))
    }
    public func subtracting<B: ExactScalarAdmission & ~Copyable>(_ other: Self, usage: inout B) throws -> Self {
        try Self(original.subtracting(other.original, usage: &usage))
    }
    public func multiplied<B: ExactScalarAdmission & ~Copyable>(by other: Self, usage: inout B) throws -> Self {
        try Self(original.multiplied(by: other.original, usage: &usage))
    }
}
