#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

/// Transports sealed child evidence through a source-issued complete affine cover.
public protocol OriginalAffineChildParameterIdentityIssuing: Sendable {
    associatedtype Source: Sendable
    associatedtype ChildFamily: OriginalChartFamilyQuerying
    func lifted<A: ExactScalarAdmission & ~Copyable>(
        _ identity: borrowing OriginalParameterIdentity<ChildFamily.Source,ChildFamily.Field>,
        through cover: borrowing OriginalAffineChildDomainCover<Source,ChildFamily>,
        limits: OriginalDomainIdentityLimits, using admission: inout A
    ) throws(OriginalDomainIdentityFailure) -> OriginalParameterIdentity<Source,ChildFamily.Field>
}
