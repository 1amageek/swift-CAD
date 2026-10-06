import CADCore

/// A reduced exact rational coefficient derived from original source bits.
public struct ExactRationalCoefficient: Equatable, Sendable {
    let sign: Int
    let numerator: ExactNaturalMagnitude
    let denominator: ExactNaturalMagnitude
    private init(sign: Int, numerator: ExactNaturalMagnitude, denominator: ExactNaturalMagnitude) {
        self.sign = numerator.isZero ? 0 : sign
        self.numerator = numerator; self.denominator = numerator.isZero ? .one : denominator
    }
    public static let zero = Self(sign: 0, numerator: .zero, denominator: .one)
    public static let one = Self(sign: 1, numerator: .one, denominator: .one)
    public var isZero: Bool { sign == 0 }
    public var isPositive: Bool { sign > 0 }
    public var isNegative: Bool { sign < 0 }
    public var canonicalSign: Int { sign }
    public var canonicalNumeratorWords: [UInt32] { numerator.words }
    public var canonicalDenominatorWords: [UInt32] { denominator.words }

    /// Reconstructs canonical original source parts under the composing caller ledger.
    public init<B: RationalAlgebraAdmitting>(canonicalSign: Int,
        numeratorWords: [UInt32], denominatorWords: [UInt32], usage: inout B) throws {
        try usage.consumeExactWork(try rationalAlgebraCount(numeratorWords.count, denominatorWords.count))
        try usage.retainExactStorage(try rationalAlgebraCount(numeratorWords.count, denominatorWords.count))
        guard (-1...1).contains(canonicalSign), numeratorWords.last != 0,
              !denominatorWords.isEmpty, denominatorWords.last != 0 else {
            throw rationalAlgebraFailure("Original rational source words are not canonical signed magnitude parts.")
        }
        let n = ExactNaturalMagnitude(numeratorWords), d = ExactNaturalMagnitude(denominatorWords)
        guard n.isZero ? canonicalSign == 0 && d == .one : canonicalSign != 0 else {
            throw rationalAlgebraFailure("Original rational zero and sign authority is inconsistent.")
        }
        let value = try Self.reduced(sign: canonicalSign, numerator: n, denominator: d, usage: &usage)
        guard value.numerator == n, value.denominator == d else {
            throw rationalAlgebraFailure("Original rational source fraction is not reduced.")
        }
        self = value
    }

    public var negated: Self { Self(sign: -sign, numerator: numerator, denominator: denominator) }

    public static func originalDouble<B: RationalAlgebraAdmitting>(_ value: Double,
                                                                   usage: inout B) throws -> Self {
        guard value.isFinite else { throw rationalAlgebraFailure("Nonfinite original rational source.") }
        if value == 0 { return .zero }
        let bits = value.bitPattern
        let exponentBits = Int((bits >> 52) & 0x7ff)
        let mantissa = bits & 0x000f_ffff_ffff_ffff | (exponentBits == 0 ? 0 : 1 << 52)
        let exponent = exponentBits == 0 ? -1074 : exponentBits - 1023 - 52
        try usage.retainExactStorage(2)
        let magnitude = ExactNaturalMagnitude([UInt32(truncatingIfNeeded: mantissa), UInt32(mantissa >> 32)])
        let n = exponent >= 0 ? try magnitude.shifted(by: exponent, usage: &usage) : magnitude
        let d = exponent < 0 ? try ExactNaturalMagnitude.one.shifted(by: -exponent, usage: &usage) : .one
        return try reduced(sign: bits >> 63 == 0 ? 1 : -1, numerator: n, denominator: d, usage: &usage)
    }
    static func natural<B: RationalAlgebraAdmitting>(_ value: Int, usage: inout B) throws -> Self {
        guard value >= 0 else { throw rationalAlgebraFailure("Negative exact polynomial exponent.") }
        let bits = UInt64(value); try usage.retainExactStorage(2)
        return Self(sign: 1, numerator: ExactNaturalMagnitude([UInt32(truncatingIfNeeded: bits), UInt32(bits >> 32)]), denominator: .one)
    }
    private static func reduced<B: RationalAlgebraAdmitting>(sign: Int,
        numerator: ExactNaturalMagnitude, denominator: ExactNaturalMagnitude, usage: inout B) throws -> Self {
        guard !denominator.isZero else { throw rationalAlgebraFailure("Exact rational division by zero.") }
        if numerator.isZero { return .zero }
        if denominator == .one { return Self(sign: sign, numerator: numerator, denominator: .one) }
        let gcd = try ExactNaturalMagnitude.gcd(numerator, denominator, usage: &usage)
        let n = try numerator.quotientAndRemainder(dividingBy: gcd, usage: &usage)
        let d = try denominator.quotientAndRemainder(dividingBy: gcd, usage: &usage)
        guard n.1.isZero, d.1.isZero else { throw rationalAlgebraFailure("Inconsistent exact rational reduction.") }
        return Self(sign: sign, numerator: n.0, denominator: d.0)
    }
    public func adding<B: RationalAlgebraAdmitting>(_ other: Self, usage: inout B) throws -> Self {
        try Task.checkCancellation(); try usage.consumeExactWork(1)
        if isZero { return other }; if other.isZero { return self }
        let lhs = try other.denominator == .one ? numerator : numerator.multiplied(by: other.denominator, usage: &usage)
        let rhs = try denominator == .one ? other.numerator : other.numerator.multiplied(by: denominator, usage: &usage)
        let denominator = try self.denominator == .one ? other.denominator
            : other.denominator == .one ? self.denominator : self.denominator.multiplied(by: other.denominator, usage: &usage)
        let magnitude: ExactNaturalMagnitude, sign: Int
        if self.sign == other.sign { magnitude = try lhs.adding(rhs, usage: &usage); sign = self.sign }
        else if lhs.compared(to: rhs) >= 0 { magnitude = try lhs.subtracting(rhs, usage: &usage); sign = self.sign }
        else { magnitude = try rhs.subtracting(lhs, usage: &usage); sign = other.sign }
        return try Self.reduced(sign: sign, numerator: magnitude, denominator: denominator, usage: &usage)
    }
    public func subtracting<B: RationalAlgebraAdmitting>(_ other: Self, usage: inout B) throws -> Self {
        try adding(other.negated, usage: &usage)
    }
    public func multiplied<B: RationalAlgebraAdmitting>(by other: Self, usage: inout B) throws -> Self {
        try Task.checkCancellation(); try usage.consumeExactWork(1)
        if isZero || other.isZero { return .zero }
        if numerator == .one && denominator == .one { return sign > 0 ? other : other.negated }
        if other.numerator == .one && other.denominator == .one { return other.sign > 0 ? self : negated }
        return try Self.reduced(sign: sign * other.sign,
            numerator: numerator.multiplied(by: other.numerator, usage: &usage),
            denominator: denominator.multiplied(by: other.denominator, usage: &usage), usage: &usage)
    }
    public func divided<B: RationalAlgebraAdmitting>(by other: Self, usage: inout B) throws -> Self {
        try Task.checkCancellation(); try usage.consumeExactWork(1)
        guard !other.isZero else { throw rationalAlgebraFailure("Exact rational division by zero.") }
        if isZero { return .zero }
        if other.numerator == .one && other.denominator == .one { return other.sign > 0 ? self : negated }
        return try Self.reduced(sign: sign * other.sign,
            numerator: numerator.multiplied(by: other.denominator, usage: &usage),
            denominator: denominator.multiplied(by: other.numerator, usage: &usage), usage: &usage)
    }
}
