#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Whole normalized generator coverage; all supplied chart sides remain distinct.
public protocol OriginalFiniteRevolutionLawPreparing: OriginalRevolutionLawIssuing {
    func prepare<A:ExactScalarAdmission & ~Copyable>(source:borrowing OriginalSourceBinding<Source>,
        generators:borrowing [OriginalRationalChartReceipt<Source.Generator,GeneratorSelection,Field>],
        field:borrowing Field,axisLength:Field.Value,maximumCharts:Int,limits:OriginalSourceIssuanceLimits,
        using admission:inout A) throws(OriginalSourceIssuanceFailure) -> OriginalFiniteRevolutionLawFamily<Source,GeneratorSelection,Field>
}
