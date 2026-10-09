#if SOURCE_ISSUED_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
@testable import DI
#elseif ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

/// Binds finite issued laws to an authoritative requested source frame.
public protocol OriginalIssuedDomainBinding: Sendable {
    associatedtype Source: Sendable
    associatedtype Selection: Sendable
    associatedtype Field: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting
    func bind<A: ExactScalarAdmission & ~Copyable>(
        laws: borrowing [OriginalRationalChartReceipt<Source, Selection, Field>],
        request: borrowing OriginalParameterSelection<Source, Field>,
        limits: OriginalDomainIdentityLimits, using admission: inout A
    ) throws(OriginalDomainIdentityFailure) -> OriginalIssuedDomainCover<Source, Selection, Field>
}
