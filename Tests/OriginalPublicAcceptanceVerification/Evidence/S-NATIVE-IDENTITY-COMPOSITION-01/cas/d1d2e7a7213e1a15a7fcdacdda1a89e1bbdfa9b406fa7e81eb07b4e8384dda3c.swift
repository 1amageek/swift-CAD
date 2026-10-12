#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

public protocol OriginalFiniteGuideChartPreparing {
    associatedtype Source:OriginalGuideSourceReading
    associatedtype ChildSelection:Sendable
    associatedtype Field:ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting where Field.Source == Field.Value,Source.Coefficient == Field.Value
    func prepare<A:ExactScalarAdmission & ~Copyable>(source:borrowing OriginalSourceBinding<Source>,
        traversals:borrowing [[OriginalRationalChartReceipt<Source.Traversal,ChildSelection,Field>]],field:borrowing Field,
        maximumCharts:Int,limits:OriginalSourceIssuanceLimits,using a:inout A) throws(OriginalSourceIssuanceFailure)
        -> OriginalFiniteGuideChartFamily<Source,ChildSelection,Field>
}
