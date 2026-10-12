#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// One whole original fiber is constant, while its UV coordinates remain distinct.
public struct OriginalSourceCollapsedFiberReceipt<S: Sendable,F: ExactScalarArithmetic & ExactScalarOrdering>: Sendable {
    public let anchor: OriginalSourceChart<S,Int>
    public let fixedAxis: Int
    public let fixedValue: F.Value
    public let varyingAxis: Int
    public let position: [F.Value]
    init(anchor: OriginalSourceChart<S,Int>,fixedAxis: Int,fixedValue: F.Value,varyingAxis: Int,position: [F.Value]) {
        self.anchor = anchor; self.fixedAxis = fixedAxis; self.fixedValue = fixedValue; self.varyingAxis = varyingAxis; self.position = position
    }
}
