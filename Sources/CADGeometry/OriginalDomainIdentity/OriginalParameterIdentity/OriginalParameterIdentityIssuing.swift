#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

public protocol OriginalParameterIdentityIssuing: Sendable {
    associatedtype Source: Sendable
    associatedtype Field: ExactScalarArithmetic & ExactScalarOrdering
    func authored<A: ExactScalarAdmission & ~Copyable>(left: borrowing OriginalParameterTransport<Source,Field>,
        right: borrowing OriginalParameterTransport<Source,Field>,limits: OriginalDomainIdentityLimits,
        using admission: inout A) throws(OriginalDomainIdentityFailure) -> OriginalParameterIdentity<Source,Field>
}
