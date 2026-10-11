#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Keeps both complete child proofs and their distinct original owners alive.
public struct OriginalRuledChartSelection<First: Sendable, FirstSelection: Sendable,
    Second: Sendable, SecondSelection: Sendable,
    Field: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: Sendable {
    public let first: OriginalRationalChartReceipt<First, FirstSelection, Field>
    public let second: OriginalRationalChartReceipt<Second, SecondSelection, Field>
    public init(first: OriginalRationalChartReceipt<First, FirstSelection, Field>,
        second: OriginalRationalChartReceipt<Second, SecondSelection, Field>) {
        self.first = first; self.second = second
    }
}
