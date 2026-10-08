#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Corner charts can differ from the selected position chart of the same source.
public struct OriginalCoonsBoundarySelection<Source: Sendable, Selection: Sendable,
    Field: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: Sendable {
    public let curve: OriginalRationalChartReceipt<Source, Selection, Field>
    public let start: OriginalCurveEndpointReceipt<Source, Selection, Field>
    public let end: OriginalCurveEndpointReceipt<Source, Selection, Field>
    public init(curve: OriginalRationalChartReceipt<Source, Selection, Field>,
        start: OriginalCurveEndpointReceipt<Source, Selection, Field>,
        end: OriginalCurveEndpointReceipt<Source, Selection, Field>) {
        self.curve = curve; self.start = start; self.end = end
    }
}
