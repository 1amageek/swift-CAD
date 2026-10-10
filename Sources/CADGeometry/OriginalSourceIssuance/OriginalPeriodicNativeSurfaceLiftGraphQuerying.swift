#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

public protocol OriginalPeriodicNativeSurfaceLiftGraphQuerying: Sendable {
    associatedtype Source: OriginalSurfaceLiftSourceReading
    var source: OriginalSourceBinding<Source> { get }
    var field: OriginalExactScalarDomain { get }
    var templateCount: Int { get }
    var integerFamilyRank: Int { get }
    func graph<A: ExactScalarAdmission & ~Copyable>(template: Int,
        cycles: borrowing [ExactRationalCoefficient],maximumCharts: Int,
        limits: OriginalSourceIssuanceLimits,using admission: inout A)
        throws(OriginalSourceIssuanceFailure)
        -> OriginalParametricGraphReceipt<Source,OriginalExactScalarDomain,OriginalSurfaceLiftGraphEvidence<Source>>
}
