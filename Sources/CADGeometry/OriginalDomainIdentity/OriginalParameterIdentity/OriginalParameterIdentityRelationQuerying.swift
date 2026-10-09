#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

/// Whole scoped relations for consumers that compile structural exclusion predicates.
public protocol OriginalParameterIdentityRelationQuerying: OriginalParameterIdentityQuerying {
    func relation<A: ExactScalarAdmission & ~Copyable>(
        of receipt: borrowing OriginalParameterIdentity<Source,Field>,
        limits: OriginalDomainIdentityLimits, using admission: inout A
    ) throws(OriginalDomainIdentityFailure) -> OriginalParameterIdentityRelation<Source,Field>
}
