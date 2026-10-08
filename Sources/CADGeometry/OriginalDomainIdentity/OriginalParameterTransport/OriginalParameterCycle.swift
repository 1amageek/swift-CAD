#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

public struct OriginalParameterCycle: Sendable {
    public let original: ExactRationalCoefficient
    public init<A: ExactScalarAdmission & ~Copyable>(exact integer: ExactRationalCoefficient, using admission: inout A)
        throws(OriginalDomainIdentityFailure) {
        original = try OriginalDomainAccess.run(&admission) { a in
            guard integer.canonicalDenominatorWords == [1] else { throw OriginalDomainIdentityFailure.invalidDomain }
            return try ExactRationalScalarDomain().importing(integer,using:&a)
        }
    }
    func scalar<F: ExactScalarArithmetic & ExactScalarOrdering,A: ExactScalarAdmission & ~Copyable>(
        in field: F, using admission: inout A) throws -> F.Value {
        let base = try field.integer(UInt64(1)<<32,using:&admission)
        var value = try field.integer(0,using:&admission)
        for word in original.canonicalNumeratorWords.reversed() {
            try admission.consumeWork(1)
            value = try field.adding(field.multiplying(value,base,using:&admission),field.integer(word,using:&admission),using:&admission)
        }
        return original.isNegative ? try field.negated(value,using:&admission) : value
    }
}
