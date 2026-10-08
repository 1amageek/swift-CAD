#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Whole cyclic-storage theorem, not a period inferred from sampled positions.
public struct OriginalSourcePeriodReceipt<Source: Sendable,F: ExactScalarArithmetic & ExactScalarOrdering>: Sendable {
    public let anchor: OriginalSourceChart<Source,Int>
    public let field: F
    public let meaning: OriginalSourceParameterMeaning
    public let axis: Int
    public let period: F.Value
    public let lower: F.Value
    public let upper: F.Value
    public var source: OriginalSourceBinding<Source> { anchor.binding }
    init(anchor: OriginalSourceChart<Source,Int>, field: F, meaning: OriginalSourceParameterMeaning, axis: Int, period: F.Value, lower: F.Value, upper: F.Value) {
        self.anchor = anchor; self.field = field; self.meaning = meaning; self.axis = axis
        self.period = period; self.lower = lower; self.upper = upper
    }
}
