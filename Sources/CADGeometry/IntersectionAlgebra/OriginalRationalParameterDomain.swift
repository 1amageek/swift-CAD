/// Closed original coordinate bounds; nil endpoints are genuine infinities.
public struct OriginalRationalParameterDomain: Equatable, Sendable {
    public let lower: ExactRationalCoefficient?
    public let upper: ExactRationalCoefficient?

    public init<B: ExactScalarAdmission & ~Copyable>(lower: ExactRationalCoefficient?,
        upper: ExactRationalCoefficient?, usage: inout B) throws {
        try intersectionAlgebraStep(&usage)
        if let lower, let upper, try upper.subtracting(lower, usage: &usage).isNegative {
            throw rationalAlgebraFailure("An original rational coordinate domain has reversed bounds.")
        }
        self.lower = lower; self.upper = upper
    }

    public init<B: ExactScalarAdmission & ~Copyable>(_ original: ScalarInterval?, usage: inout B) throws {
        try self.init(lower: original.map { try .originalDouble($0.lower, usage: &usage) },
            upper: original.map { try .originalDouble($0.upper, usage: &usage) }, usage: &usage)
    }

    /// Nil certifies disjoint closed domains by their exact bound order.
    public func intersecting<B: ExactScalarAdmission & ~Copyable>(_ other: Self, usage: inout B) throws -> Self? {
        try intersectionAlgebraStep(&usage)
        let lower: ExactRationalCoefficient?, upper: ExactRationalCoefficient?
        switch (self.lower, other.lower) {
        case (nil, let b): lower = b
        case (let a, nil): lower = a
        case (let a?, let b?): lower = try a.subtracting(b, usage: &usage).isNegative ? b : a
        }
        switch (self.upper, other.upper) {
        case (nil, let b): upper = b
        case (let a, nil): upper = a
        case (let a?, let b?): upper = try a.subtracting(b, usage: &usage).isPositive ? b : a
        }
        if let lower, let upper, try upper.subtracting(lower, usage: &usage).isNegative { return nil }
        return try Self(lower: lower, upper: upper, usage: &usage)
    }
}
