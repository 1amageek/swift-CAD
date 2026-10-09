#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

extension DefaultOriginalParameterIdentityIssuer: OriginalParameterIdentityRelationQuerying {
    public func relation<A: ExactScalarAdmission & ~Copyable>(
        of receipt: borrowing OriginalParameterIdentity<S,F>,
        limits: OriginalDomainIdentityLimits, using admission: inout A
    ) throws(OriginalDomainIdentityFailure) -> OriginalParameterIdentityRelation<S,F> {
        let retained = copy receipt
        return try OriginalDomainAccess.run(&admission) { a in
            try require(retained,limits,&a)
            // The proof owner and word are shared; this view generates no new payload.
            return .init(receipt:retained)
        }
    }
}
