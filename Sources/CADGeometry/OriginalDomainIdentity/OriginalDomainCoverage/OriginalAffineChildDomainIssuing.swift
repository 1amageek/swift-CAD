#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

/// Source-specific affine composition of an already complete child family.
public protocol OriginalAffineChildDomainIssuing: Sendable {
    associatedtype Source: Sendable
    associatedtype ChildFamily: OriginalChartFamilyQuerying
    func issue<A: ExactScalarAdmission & ~Copyable>(
        source: borrowing OriginalSourceBinding<Source>, child: borrowing ChildFamily,
        requested: borrowing [[ExactParameterInterval<ChildFamily.Field.Value>]]?,
        limits: OriginalDomainIdentityLimits, using admission: inout A
    ) throws(OriginalDomainIdentityFailure) -> OriginalAffineChildDomainCover<Source, ChildFamily>
}
