#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Explicit physical source capability; its pi field is selected by the caller.
public struct DefaultOriginalPhysicalAnalyticCoordinateIssuer<S: OriginalAnalyticCoordinateReading,F: OriginalPiGenerating>: OriginalAnalyticCoordinateIssuing {
    public typealias Source = S
    public typealias Field = F
    public init() {}
    public func issue<A: ExactScalarAdmission & ~Copyable>(source: borrowing OriginalSourceBinding<S>,field: borrowing F,
        limits: OriginalSourceIssuanceLimits,using admission: inout A) throws(OriginalSourceIssuanceFailure) -> OriginalAnalyticCoordinateLawReceipt<S,F> {
        try DefaultOriginalAnalyticCoordinateIssuer<S,F>().issuePhysical(source:source,field:field,limits:limits,using:&admission)
    }
}
