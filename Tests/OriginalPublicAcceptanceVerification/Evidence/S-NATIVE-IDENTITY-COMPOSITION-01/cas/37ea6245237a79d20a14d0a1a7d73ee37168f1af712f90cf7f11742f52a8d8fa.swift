#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

public protocol OriginalAnalyticDomainIssuing: Sendable {
    associatedtype Source: OriginalAnalyticCoordinateReading
    associatedtype Field: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting
    func frame<A: ExactScalarAdmission & ~Copyable>(law: borrowing OriginalAnalyticCoordinateLawReceipt<Source,Field>,
        limits: OriginalDomainIdentityLimits,using admission: inout A) throws(OriginalDomainIdentityFailure) -> OriginalParameterFrame<Source,Field>
    func issue<A: ExactScalarAdmission & ~Copyable>(request: borrowing OriginalParameterSelection<Source,Field>,
        law: borrowing OriginalAnalyticCoordinateLawReceipt<Source,Field>,limits: OriginalDomainIdentityLimits,using admission: inout A
    ) throws(OriginalDomainIdentityFailure) -> OriginalAnalyticDomainCover<Source,Field>
}
