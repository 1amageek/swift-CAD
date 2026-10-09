#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

/// Complete guarded source family; Cartesian enclosures never imply position membership.
public protocol OriginalGuardedChartFamilyQuerying: Sendable {
    associatedtype Source: Sendable
    associatedtype Field: ExactScalarArithmetic & ExactScalarOrdering
    associatedtype Occurrence: Sendable
    var source: OriginalSourceBinding<Source> { get }
    var enclosingSupport: OriginalParameterSelection<Source,Field> { get }
    var request: OriginalParameterSelection<Source,Field> { get }
    var effectiveEnclosure: OriginalParameterSelection<Source,Field> { get }
    var templateCount: Int { get }
    func member<A: ExactScalarAdmission & ~Copyable>(template: Int,limits: OriginalDomainIdentityLimits,
        using admission: inout A) throws(OriginalDomainIdentityFailure) -> Occurrence
    func positionIncidents<A: ExactScalarAdmission & ~Copyable>(at tuple: borrowing [Field.Value],
        limits: OriginalDomainIdentityLimits,using admission: inout A)
        throws(OriginalDomainIdentityFailure) -> [Occurrence]
    func liftedPositionIncidents<A: ExactScalarAdmission & ~Copyable>(at tuple: borrowing [Field.Value],
        limits: OriginalDomainIdentityLimits,using admission: inout A)
        throws(OriginalDomainIdentityFailure) -> [Occurrence]
}
