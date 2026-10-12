#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

extension OriginalParameterCycle {
    /// Exact floor in any ordered Archimedean source field. No binary64 estimate
    /// or fixed-width integer is used; nontermination stops at the caller budget.
    static func floor<F: ExactScalarArithmetic & ExactScalarOrdering,A: ExactScalarAdmission & ~Copyable>(
        _ x: F.Value, field: F, using a: inout A) throws -> Self {
        let q = ExactRationalScalarDomain()
        let zero = try q.integer(0,using:&a), one = try q.integer(1,using:&a), two = try q.integer(2,using:&a)
        var lo = zero, hi = one
        let sign = try field.sign(of:x,using:&a)
        if sign == .negative { lo = try q.negated(one,using:&a); hi = zero }
        while true {
            try a.consumeWork(1)
            let bound = try Self(exact:sign == .negative ? lo : hi,using:&a).scalar(in:field,using:&a)
            let order = try field.compare(x,bound,using:&a)
            if sign == .negative ? order != .less : order == .less { break }
            if sign == .negative { lo = try q.multiplying(lo,two,using:&a) }
            else { hi = try q.multiplying(hi,two,using:&a) }
        }
        while try q.compare(q.subtracting(hi,lo,using:&a),one,using:&a) != .equal {
            try a.consumeWork(1)
            let mid = try q.dividing(q.adding(lo,hi,using:&a),two,using:&a)
            let value = try Self(exact:mid,using:&a).scalar(in:field,using:&a)
            if try field.compare(x,value,using:&a) == .less { hi = mid } else { lo = mid }
        }
        return try .init(exact:lo,using:&a)
    }
}
