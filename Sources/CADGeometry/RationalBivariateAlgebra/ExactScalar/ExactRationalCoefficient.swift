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
    public init<B: ExactScalarAdmission & ~Copyable>(canonicalSign: Int,
        numeratorWords: [UInt32], denominatorWords: [UInt32], usage: inout B) throws {
        try usage.consumeWork(try exactScalarCount(numeratorWords.count, denominatorWords.count))
        try usage.retainStorage(bytes: exactScalarPayloadBytes(count: try exactScalarCount(numeratorWords.count, denominatorWords.count), of: UInt32.self))
        guard (-1...1).contains(canonicalSign), numeratorWords.last != 0,
              !denominatorWords.isEmpty, denominatorWords.last != 0 else {
            throw ExactScalarFailure.invalidSource
        }
        let n = ExactNaturalMagnitude(numeratorWords), d = ExactNaturalMagnitude(denominatorWords)
        guard n.isZero ? canonicalSign == 0 && d == .one : canonicalSign != 0 else {
            throw ExactScalarFailure.invalidSource
        }
        let value = try Self.reduced(sign: canonicalSign, numerator: n, denominator: d, usage: &usage)
        guard value.numerator == n, value.denominator == d else {
            throw ExactScalarFailure.invalidSource
        }
        self = value
    }

    public var negated: Self { Self(sign: -sign, numerator: numerator, denominator: denominator) }

    public static func originalDouble<B: ExactScalarAdmission & ~Copyable>(_ value: Double,
                                                                   usage: inout B) throws -> Self {
        guard value.isFinite else { throw ExactScalarFailure.invalidSource }
        if value == 0 { return .zero }
        let bits = value.bitPattern
        let exponentBits = Int((bits >> 52) & 0x7ff)
        let mantissa = bits & 0x000f_ffff_ffff_ffff | (exponentBits == 0 ? 0 : 1 << 52)
        let exponent = exponentBits == 0 ? -1074 : exponentBits - 1023 - 52
        try usage.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: UInt32.self))
        let magnitude = ExactNaturalMagnitude([UInt32(truncatingIfNeeded: mantissa), UInt32(mantissa >> 32)])
        let n = exponent >= 0 ? try magnitude.shifted(by: exponent, usage: &usage) : magnitude
        let d = exponent < 0 ? try ExactNaturalMagnitude.one.shifted(by: -exponent, usage: &usage) : .one
        return try reduced(sign: bits >> 63 == 0 ? 1 : -1, numerator: n, denominator: d, usage: &usage)
    }
    static func originalInteger<I: BinaryInteger, B: ExactScalarAdmission & ~Copyable>(_ source: I, usage: inout B) throws -> Self {
        if source == 0 { return .zero }
        let words = source.magnitude.words
        let count = try exactScalarCount(words.count, UInt.bitWidth / 32, multiply: true)
        try usage.consumeWork(count); try usage.retainStorage(bytes: exactScalarPayloadBytes(count: count, of: UInt32.self))
        var output: [UInt32] = []; output.reserveCapacity(count)
        for word in words {
            output.append(UInt32(truncatingIfNeeded: word))
            if UInt.bitWidth > 32 { output.append(UInt32(truncatingIfNeeded: word >> 32)) }
        }
        return Self(sign: source < 0 ? -1 : 1, numerator: ExactNaturalMagnitude(output), denominator: .one)
    }

    static func natural<B: ExactScalarAdmission & ~Copyable>(_ value: Int, usage: inout B) throws -> Self {
        guard value >= 0 else { throw exactScalarBackendFailure("Negative exact polynomial exponent.") }
        let bits = UInt64(value); try usage.retainStorage(bytes: exactScalarPayloadBytes(count: 2, of: UInt32.self))
        return Self(sign: 1, numerator: ExactNaturalMagnitude([UInt32(truncatingIfNeeded: bits), UInt32(bits >> 32)]), denominator: .one)
    }
    private static func reduced<B: ExactScalarAdmission & ~Copyable>(sign: Int,
        numerator: ExactNaturalMagnitude, denominator: ExactNaturalMagnitude, usage: inout B) throws -> Self {
        try usage.consumeWork(exactScalarCount(numerator.words.count, denominator.words.count))
        guard !denominator.isZero else { throw exactScalarBackendFailure("Exact rational division by zero.") }
        if numerator.isZero { return .zero }
        if denominator == .one { return Self(sign: sign, numerator: numerator, denominator: .one) }
        if numerator == .one { return Self(sign: sign, numerator: numerator, denominator: denominator) }
        if let exponent = try denominator.powerOfTwoExponent(usage: &usage) {
            let common = min(exponent, try numerator.trailingZeroBits(usage: &usage))
            if common == 0 { return Self(sign: sign, numerator: numerator, denominator: denominator) }
            return try Self(sign: sign, numerator: numerator.shiftedRight(by: common, usage: &usage),
                denominator: denominator.shiftedRight(by: common, usage: &usage))
        }
        let gcd = try ExactNaturalMagnitude.gcd(numerator, denominator, usage: &usage)
        if gcd == .one { return Self(sign: sign, numerator: numerator, denominator: denominator) }
        let n = try numerator.quotientAndRemainder(dividingBy: gcd, usage: &usage)
        let d = try denominator.quotientAndRemainder(dividingBy: gcd, usage: &usage)
        guard n.1.isZero, d.1.isZero else { throw exactScalarBackendFailure("Inconsistent exact rational reduction.") }
        return Self(sign: sign, numerator: n.0, denominator: d.0)
    }
    private static func dividedMagnitude<B: ExactScalarAdmission & ~Copyable>(_ value: ExactNaturalMagnitude,
        by divisor: ExactNaturalMagnitude, usage: inout B) throws -> ExactNaturalMagnitude {
        if divisor == .one { return value }
        let result = try value.quotientAndRemainder(dividingBy: divisor, usage: &usage)
        guard result.1.isZero else { throw exactScalarBackendFailure("Canonical rational cancellation has a nonzero remainder.") }
        return result.0
    }
    public func adding<B: ExactScalarAdmission & ~Copyable>(_ other: Self, usage: inout B) throws -> Self {
        try usage.checkpoint()
        let firstWords = try exactScalarCount(numerator.words.count, denominator.words.count)
        let secondWords = try exactScalarCount(other.numerator.words.count, other.denominator.words.count)
        try usage.consumeWork(exactScalarCount(firstWords, secondWords))
        if isZero { return other }; if other.isZero { return self }
        if denominator == other.denominator {
            let magnitude: ExactNaturalMagnitude, resultSign: Int
            if sign == other.sign { magnitude = try numerator.adding(other.numerator, usage: &usage); resultSign = sign }
            else if numerator.compared(to: other.numerator) >= 0 {
                magnitude = try numerator.subtracting(other.numerator, usage: &usage); resultSign = sign
            } else {
                magnitude = try other.numerator.subtracting(numerator, usage: &usage); resultSign = other.sign
            }
            return try Self.reduced(sign: resultSign, numerator: magnitude, denominator: denominator, usage: &usage)
        }
        let common = try ExactNaturalMagnitude.gcd(denominator, other.denominator, usage: &usage)
        let firstScale = try Self.dividedMagnitude(other.denominator, by: common, usage: &usage)
        let secondScale = try Self.dividedMagnitude(denominator, by: common, usage: &usage)
        let lhs = try firstScale == .one ? numerator : numerator.multiplied(by: firstScale, usage: &usage)
        let rhs = try secondScale == .one ? other.numerator : other.numerator.multiplied(by: secondScale, usage: &usage)
        let magnitude: ExactNaturalMagnitude, sign: Int
        if self.sign == other.sign { magnitude = try lhs.adding(rhs, usage: &usage); sign = self.sign }
        else if lhs.compared(to: rhs) >= 0 { magnitude = try lhs.subtracting(rhs, usage: &usage); sign = self.sign }
        else { magnitude = try rhs.subtracting(lhs, usage: &usage); sign = other.sign }
        if magnitude.isZero {
            try usage.checkpoint()
            return .zero
        }
        // Canonical operands make the combined numerator coprime to both
        // denominator/common scales; only the retained common GCD can cancel.
        let cancellation = try common == .one ? .one : ExactNaturalMagnitude.gcd(magnitude, common, usage: &usage)
        let resultNumerator = try Self.dividedMagnitude(magnitude, by: cancellation, usage: &usage)
        let remainingDenominator = try Self.dividedMagnitude(other.denominator, by: cancellation, usage: &usage)
        let resultDenominator = try secondScale == .one ? remainingDenominator
            : secondScale.multiplied(by: remainingDenominator, usage: &usage)
        try usage.checkpoint()
        return Self(sign: sign, numerator: resultNumerator, denominator: resultDenominator)
    }
    public func subtracting<B: ExactScalarAdmission & ~Copyable>(_ other: Self, usage: inout B) throws -> Self {
        try adding(other.negated, usage: &usage)
    }
    public func multiplied<B: ExactScalarAdmission & ~Copyable>(by other: Self, usage: inout B) throws -> Self {
        try usage.checkpoint()
        let firstWords = try exactScalarCount(numerator.words.count, denominator.words.count)
        let secondWords = try exactScalarCount(other.numerator.words.count, other.denominator.words.count)
        try usage.consumeWork(exactScalarCount(firstWords, secondWords))
        if isZero || other.isZero { return .zero }
        if numerator == .one && denominator == .one { return sign > 0 ? other : other.negated }
        if other.numerator == .one && other.denominator == .one { return other.sign > 0 ? self : negated }
        let firstCommon = try ExactNaturalMagnitude.gcd(numerator, other.denominator, usage: &usage)
        let secondCommon = try ExactNaturalMagnitude.gcd(other.numerator, denominator, usage: &usage)
        let firstNumerator = try Self.dividedMagnitude(numerator, by: firstCommon, usage: &usage)
        let secondNumerator = try Self.dividedMagnitude(other.numerator, by: secondCommon, usage: &usage)
        let firstDenominator = try Self.dividedMagnitude(denominator, by: secondCommon, usage: &usage)
        let secondDenominator = try Self.dividedMagnitude(other.denominator, by: firstCommon, usage: &usage)
        return try Self(sign: sign * other.sign,
            numerator: firstNumerator.multiplied(by: secondNumerator, usage: &usage),
            denominator: firstDenominator.multiplied(by: secondDenominator, usage: &usage))
    }
    public func divided<B: ExactScalarAdmission & ~Copyable>(by other: Self, usage: inout B) throws -> Self {
        try usage.checkpoint()
        let firstWords = try exactScalarCount(numerator.words.count, denominator.words.count)
        let secondWords = try exactScalarCount(other.numerator.words.count, other.denominator.words.count)
        try usage.consumeWork(exactScalarCount(firstWords, secondWords))
        guard !other.isZero else { throw exactScalarBackendFailure("Exact rational division by zero.") }
        if isZero { return .zero }
        if other.numerator == .one && other.denominator == .one { return other.sign > 0 ? self : negated }
        return try multiplied(by: Self(sign: other.sign, numerator: other.denominator, denominator: other.numerator), usage: &usage)
    }
}


extension ExactRationalCoefficient {
    /// Exact floor/ceiling on a dyadic grid, using the existing integer backend.
    static func dyadicNeighbours<B: ExactScalarAdmission & ~Copyable>(_ value: Self, fractionalBits: Int,
        usage: inout B) throws -> (lower: Self, upper: Self) {
        guard fractionalBits >= 0 else { throw ExactScalarFailure.invalidSource }
        let scaled = try value.numerator.shifted(by: fractionalBits, usage: &usage)
        let (quotient, remainder) = try scaled.quotientAndRemainder(dividingBy: value.denominator, usage: &usage)
        let denominator = try ExactNaturalMagnitude.one.shifted(by: fractionalBits, usage: &usage)
        let next = remainder.isZero ? quotient :
            try quotient.adding(.one, usage: &usage)
        let low = try reduced(sign: value.sign, numerator: value.sign < 0 ? next : quotient,
            denominator: denominator, usage: &usage)
        let high = try reduced(sign: value.sign, numerator: value.sign < 0 ? quotient : next,
            denominator: denominator, usage: &usage)
        return (low, high)
    }
}
