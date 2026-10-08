#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

public protocol OriginalDomainCoverQuerying: Sendable {
    associatedtype Source: Sendable
    associatedtype Field: ExactScalarArithmetic & ExactScalarOrdering
    var support: OriginalParameterSelection<Source,Field> { get }
    var request: OriginalParameterSelection<Source,Field> { get }
    var effective: OriginalParameterSelection<Source,Field> { get }
    var charts: ArraySlice<OriginalDomainChart<Source,Field>> { get }
    func incident<A: ExactScalarAdmission & ~Copyable>(at tuple: borrowing [Field.Value],
        limits: OriginalDomainIdentityLimits,using admission: inout A) throws(OriginalDomainIdentityFailure) -> [Int]
}
