#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

public protocol OriginalPlaneCoordinateQuerying: Sendable {
    associatedtype Field: ExactScalarArithmetic & ExactScalarOrdering
    func position<A: ExactScalarAdmission & ~Copyable>(u x: Field.Value,v y: Field.Value,limits: OriginalDomainIdentityLimits,
        using admission: inout A) throws(OriginalDomainIdentityFailure) -> [Field.Value]
    func parameters<A: ExactScalarAdmission & ~Copyable>(of point: borrowing [Field.Value],limits: OriginalDomainIdentityLimits,
        using admission: inout A) throws(OriginalDomainIdentityFailure) -> [Field.Value]
}
