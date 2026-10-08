#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Retains the complete child law and its original parameter correspondence.
public struct OriginalSpatialChartSelection<Child: Sendable, ChildSelection: Sendable,
    Field: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: Sendable {
    public let child: OriginalRationalChartReceipt<Child, ChildSelection, Field>
    public init(child: OriginalRationalChartReceipt<Child, ChildSelection, Field>) { self.child = child }
}
