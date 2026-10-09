#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

/// Complete selected chart family over retained original source coordinates.
/// Cycles have authored arity; every nonperiodic coordinate must carry zero.
/// Membership does not merge coincident XYZ values or distinct chart sides.
public protocol OriginalChartFamilyQuerying: Sendable {
    associatedtype Source: Sendable
    associatedtype Field: ExactScalarArithmetic & ExactScalarOrdering
    associatedtype Occurrence: Sendable
    var source: OriginalSourceBinding<Source> { get }
    var support: OriginalParameterSelection<Source, Field> { get }
    var request: OriginalParameterSelection<Source, Field> { get }
    var effective: OriginalParameterSelection<Source, Field> { get }
    var templateCount: Int { get }
    var integerFamilyRank: Int { get }
    func member<A: ExactScalarAdmission & ~Copyable>(
        template: Int, cycles: borrowing [OriginalParameterCycle],
        limits: OriginalDomainIdentityLimits, using admission: inout A
    ) throws(OriginalDomainIdentityFailure) -> Occurrence
    func incident<A: ExactScalarAdmission & ~Copyable>(
        at tuple: borrowing [Field.Value], limits: OriginalDomainIdentityLimits,
        using admission: inout A
    ) throws(OriginalDomainIdentityFailure) -> [Occurrence]
}
