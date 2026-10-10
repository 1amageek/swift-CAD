#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

/// Lifts a sealed child identity through independently bound parent covers.
public protocol OriginalAffinePairedParameterIdentityIssuing: Sendable {
    associatedtype Source: Sendable
    associatedtype LeftFamily: OriginalChartFamilyQuerying
    associatedtype RightFamily: OriginalChartFamilyQuerying where RightFamily.Source == LeftFamily.Source, RightFamily.Field == LeftFamily.Field
    func lifted<A: ExactScalarAdmission & ~Copyable>(
        _ identity: borrowing OriginalParameterIdentity<LeftFamily.Source,LeftFamily.Field>,
        from left: borrowing OriginalAffineChildDomainCover<Source,LeftFamily>,
        to right: borrowing OriginalAffineChildDomainCover<Source,RightFamily>,
        leftAction: borrowing OriginalSourceAffineActionReceipt<Source,LeftFamily.Field>,
        rightAction: borrowing OriginalSourceAffineActionReceipt<Source,LeftFamily.Field>,
        limits: OriginalDomainIdentityLimits, using admission: inout A
    ) throws(OriginalDomainIdentityFailure) -> OriginalParameterIdentity<Source,LeftFamily.Field>
}
