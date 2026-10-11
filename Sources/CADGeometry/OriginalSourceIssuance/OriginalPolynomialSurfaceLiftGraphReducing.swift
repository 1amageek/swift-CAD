#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

public protocol OriginalPolynomialSurfaceLiftGraphReducing: Sendable {
    associatedtype Source: OriginalLiftGraphSourceReading
    func reduce<A: ExactScalarAdmission & ~Copyable>(
        _ graph: borrowing OriginalPolynomialSurfaceLiftGraphReduction<Source>.Graph,
        limits: OriginalSourceIssuanceLimits,using admission: inout A)
        throws(OriginalSourceIssuanceFailure) -> OriginalPolynomialSurfaceLiftGraphReduction<Source>
}
