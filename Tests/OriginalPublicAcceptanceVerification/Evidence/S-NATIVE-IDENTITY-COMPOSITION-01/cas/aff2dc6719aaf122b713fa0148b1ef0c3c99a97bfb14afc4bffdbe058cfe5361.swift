#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Closed exact support of the implemented Native local representation.
public struct OriginalSourceParameterInterval<Value: Sendable>: Sendable {
    public let lower: Value
    public let upper: Value
    init(lower: Value, upper: Value) { self.lower = lower; self.upper = upper }
}
