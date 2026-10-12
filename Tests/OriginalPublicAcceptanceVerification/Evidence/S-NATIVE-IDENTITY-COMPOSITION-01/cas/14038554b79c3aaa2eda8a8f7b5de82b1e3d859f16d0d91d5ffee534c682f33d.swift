#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

public protocol OriginalParametricGraphDomainBinding: Sendable {
    associatedtype Source: Sendable
    associatedtype Field: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting
    associatedtype Evidence: Sendable
    func bind<A: ExactScalarAdmission & ~Copyable>(graph: borrowing OriginalParametricGraphReceipt<Source,Field,Evidence>,
        request: borrowing OriginalParameterSelection<Source,Field>, limits: OriginalDomainIdentityLimits, using admission: inout A)
        throws(OriginalDomainIdentityFailure) -> OriginalDomainBoundParametricGraph<Source,Field,Evidence>
}
