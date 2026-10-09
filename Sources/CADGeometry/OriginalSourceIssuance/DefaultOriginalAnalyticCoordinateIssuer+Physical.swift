#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

extension DefaultOriginalAnalyticCoordinateIssuer where F: OriginalPiGenerating {
    /// Original physical phase and nonbinary poles/periods stay in Q(pi).
    public func issuePhysical<A: ExactScalarAdmission & ~Copyable>(source: borrowing OriginalSourceBinding<S>,field: borrowing F,
        limits: OriginalSourceIssuanceLimits,using admission: inout A) throws(OriginalSourceIssuanceFailure) -> OriginalAnalyticCoordinateLawReceipt<S,F> {
        do {
            let pi = try field.pi(using:&admission)
            return try issue(source:source,field:field,mathematicalPi:pi,limits:limits,using:&admission)
        } catch { throw .init(preserving:error) }
    }
}
