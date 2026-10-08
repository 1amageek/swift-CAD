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
        let first = try q.multiplying(lower, rhs.lower, using: &a)
        var lo = first, hi = first
        // The four corners are sufficient for a bilinear product on a closed box.
        for corner in 1..<4 {
            try a.consumeWork(1)
            let v = try q.multiplying(corner < 2 ? lower : upper,
                corner % 2 == 0 ? rhs.lower : rhs.upper, using: &a)
            if try q.compare(v, lo, using: &a) == .less { lo = v }
            if try q.compare(v, hi, using: &a) == .greater { hi = v }
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
