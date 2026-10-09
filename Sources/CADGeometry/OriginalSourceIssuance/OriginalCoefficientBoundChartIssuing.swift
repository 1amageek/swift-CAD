#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Explicit coefficient correspondence is separate from source/chart identity.
public protocol OriginalCoefficientBoundChartIssuing: OriginalRationalChartIssuing {
    func issue<C: OriginalSourceCoefficientImporting, A: ExactScalarAdmission & ~Copyable>(
        source: borrowing OriginalSourceBinding<Source>,
        chart: borrowing OriginalSourceChart<Source, Selection>, field: borrowing Field,
        coefficients: borrowing C, limits: OriginalSourceIssuanceLimits, using admission: inout A
    ) throws(OriginalSourceIssuanceFailure) -> OriginalRationalChartReceipt<Source, Selection, Field>
    where C.Field == Field
}
