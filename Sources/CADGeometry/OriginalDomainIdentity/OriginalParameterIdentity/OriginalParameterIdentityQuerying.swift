#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

public protocol OriginalParameterIdentityQuerying: Sendable {
    associatedtype Source: Sendable
    associatedtype Field: ExactScalarArithmetic & ExactScalarOrdering
    func decide<A: ExactScalarAdmission & ~Copyable>(_ receipt: borrowing OriginalParameterIdentity<Source,Field>,
        left: borrowing [Field.Value],right: borrowing [Field.Value],limits: OriginalDomainIdentityLimits,
        using admission: inout A) throws(OriginalDomainIdentityFailure) -> OriginalParameterIdentityDecision
    func restricted<A: ExactScalarAdmission & ~Copyable>(_ receipt: borrowing OriginalParameterIdentity<Source,Field>,
        left: borrowing OriginalParameterSelection<Source,Field>,right: borrowing OriginalParameterSelection<Source,Field>,
        limits: OriginalDomainIdentityLimits,using admission: inout A) throws(OriginalDomainIdentityFailure) -> OriginalParameterIdentity<Source,Field>
    func symmetric<A: ExactScalarAdmission & ~Copyable>(_ receipt: borrowing OriginalParameterIdentity<Source,Field>,
        limits: OriginalDomainIdentityLimits,using admission: inout A) throws(OriginalDomainIdentityFailure) -> OriginalParameterIdentity<Source,Field>
    func compose<A: ExactScalarAdmission & ~Copyable>(_ first: borrowing OriginalParameterIdentity<Source,Field>,
        _ second: borrowing OriginalParameterIdentity<Source,Field>,limits: OriginalDomainIdentityLimits,
        using admission: inout A) throws(OriginalDomainIdentityFailure) -> OriginalParameterIdentity<Source,Field>
}
