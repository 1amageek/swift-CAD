#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

/// A finite requested selection can be enumerated without flattening the
/// underlying infinite chart family or weakening its complete-cover receipt.
public protocol OriginalFiniteChartFamilyQuerying: OriginalChartFamilyQuerying {
    func selectedMembers<A: ExactScalarAdmission & ~Copyable>(limits: OriginalDomainIdentityLimits,
        using admission: inout A) throws(OriginalDomainIdentityFailure) -> [Occurrence]
}
