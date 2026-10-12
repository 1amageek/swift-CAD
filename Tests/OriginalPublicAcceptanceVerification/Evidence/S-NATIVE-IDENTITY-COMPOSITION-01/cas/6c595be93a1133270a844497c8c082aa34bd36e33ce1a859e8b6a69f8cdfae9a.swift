#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Exact guarded endpoint evidence retaining the complete original chart.
public struct OriginalCurveEndpointReceipt<Source: Sendable, Selection: Sendable,
    Field: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: Sendable {
    public let curve: OriginalRationalChartReceipt<Source, Selection, Field>
    public let localParameter: Field.Value
    public let originalParameter: Field.Value
    public let position: [Field.Value]
    public let depth: ExactScalarDepth
    init(curve: OriginalRationalChartReceipt<Source, Selection, Field>, localParameter: Field.Value,
        originalParameter: Field.Value, position: [Field.Value], depth: ExactScalarDepth) {
        self.curve = curve; self.localParameter = localParameter
        self.originalParameter = originalParameter; self.position = position; self.depth = depth
    }
}
