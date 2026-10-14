#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Exact rational closed bounds; helpers preserve lower <= upper.
struct OriginalPhysicalAngleInterval {
    let lower: ExactRationalCoefficient
    let upper: ExactRationalCoefficient
    init(_ scalar: ExactRationalCoefficient) { lower = scalar; upper = scalar }
    init(lower: ExactRationalCoefficient, upper: ExactRationalCoefficient) { self.lower = lower; self.upper = upper }
    static func ordered<A: ExactScalarAdmission & ~Copyable>(_ first: ExactRationalCoefficient,
        _ second: ExactRationalCoefficient, _ q: ExactRationalScalarDomain, _ a: inout A) throws -> Self {
        if try q.compare(first, second, using: &a) == .greater { return .init(lower: second, upper: first) }
        return .init(lower: first, upper: second)
    }
    func outwardDyadic<A: ExactScalarAdmission & ~Copyable>(
        _ q: ExactRationalScalarDomain, _ a: inout A) throws -> Self {
        let width = try q.subtracting(upper, lower, using: &a)
        let sign = try q.sign(of: width, using: &a)
        guard sign != .negative else { throw ExactScalarFailure.invalidEvidence }
        if sign == .zero { return self }
        let words = try OriginalPhysicalAngleScalarDomain.increment(max(
            width.canonicalDenominatorWords.count - width.canonicalNumeratorWords.count, 0))
        let bits = words.multipliedReportingOverflow(by: UInt32.bitWidth)
        guard !bits.overflow else { throw ExactScalarFailure.countOverflow }
        return try Self(lower: q.dyadicNeighbours(lower, fractionalBits: bits.partialValue, using: &a).lower,
            upper: q.dyadicNeighbours(upper, fractionalBits: bits.partialValue, using: &a).upper)
    }
    func adding<A: ExactScalarAdmission & ~Copyable>(_ rhs: Self,
        _ q: ExactRationalScalarDomain, _ a: inout A) throws -> Self {
        try .init(lower: q.adding(lower, rhs.lower, using: &a), upper: q.adding(upper, rhs.upper, using: &a))
    }
    func negated<A: ExactScalarAdmission & ~Copyable>(_ q: ExactRationalScalarDomain, _ a: inout A) throws -> Self {
        try .init(lower: q.negated(upper, using: &a), upper: q.negated(lower, using: &a))
    }
    func subtracting<A: ExactScalarAdmission & ~Copyable>(_ rhs: Self,
        _ q: ExactRationalScalarDomain, _ a: inout A) throws -> Self {
        try adding(rhs.negated(q, &a), q, &a)
    }
    func multiplying<A: ExactScalarAdmission & ~Copyable>(_ rhs: Self,
        _ q: ExactRationalScalarDomain, _ a: inout A) throws -> Self {
        let lhsPositive = try q.sign(of: lower, using: &a) != .negative
        let lhsNegative = try q.sign(of: upper, using: &a) != .positive
        let rhsPositive = try q.sign(of: rhs.lower, using: &a) != .negative
        let rhsNegative = try q.sign(of: rhs.upper, using: &a) != .positive
        let lo: ExactRationalCoefficient, hi: ExactRationalCoefficient
        if lhsPositive {
            lo = try q.multiplying(rhsPositive ? lower : upper, rhs.lower, using: &a)
            hi = try q.multiplying(rhsNegative ? lower : upper, rhs.upper, using: &a)
        } else if lhsNegative {
            lo = try q.multiplying(rhsNegative ? upper : lower, rhs.upper, using: &a)
            hi = try q.multiplying(rhsPositive ? upper : lower, rhs.lower, using: &a)
        } else if rhsPositive {
            lo = try q.multiplying(lower, rhs.upper, using: &a)
            hi = try q.multiplying(upper, rhs.upper, using: &a)
        } else if rhsNegative {
            lo = try q.multiplying(upper, rhs.lower, using: &a)
            hi = try q.multiplying(lower, rhs.lower, using: &a)
        } else {
            let l = try q.multiplying(lower, rhs.upper, using: &a)
            let r = try q.multiplying(upper, rhs.lower, using: &a)
            lo = try q.compare(l, r, using: &a) == .less ? l : r
            let u = try q.multiplying(lower, rhs.lower, using: &a)
            let v = try q.multiplying(upper, rhs.upper, using: &a)
            hi = try q.compare(u, v, using: &a) == .greater ? u : v
        }
        return .init(lower: lo, upper: hi)
    }
    func sign<A: ExactScalarAdmission & ~Copyable>(_ q: ExactRationalScalarDomain,
        _ a: inout A) throws -> ExactSign? {
        if try q.sign(of: lower, using: &a) == .positive { return .positive }
        if try q.sign(of: upper, using: &a) == .negative { return .negative }
        return nil
    }
    func divided<A: ExactScalarAdmission & ~Copyable>(by rhs: Self,
        _ q: ExactRationalScalarDomain, _ a: inout A) throws -> Self {
        guard try rhs.sign(q, &a) != nil else { throw ExactScalarFailure.invalidEvidence }
        let one = try q.integer(1, using: &a)
        // Reciprocal is decreasing on either connected side of zero.
        let inverse = try Self(lower: q.dividing(one, rhs.upper, using: &a),
            upper: q.dividing(one, rhs.lower, using: &a))
        return try multiplying(inverse, q, &a)
    }
    func powered<A: ExactScalarAdmission & ~Copyable>(_ exponent: Int,
        _ q: ExactRationalScalarDomain, _ a: inout A) throws -> Self {
        guard exponent >= 0 else { throw ExactScalarFailure.invalidEvidence }
        var result = Self(try q.integer(1, using: &a)), base = self, remaining = exponent
        while remaining != 0 {
            try a.consumeWork(1)
            if remaining % 2 == 1 { result = try result.multiplying(base, q, &a) }
            remaining /= 2
            if remaining != 0 { base = try base.multiplying(base, q, &a) }
        }
        return result
    }
}
