#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Exact original support; nil bounds mean negative/positive infinity.
public struct OriginalSourceCoordinateAxis<Value: Sendable>: Sendable {
    public let lower: Value?
    public let upper: Value?
    public let meaning: OriginalSourceParameterMeaning
    init(lower: Value?,upper: Value?,meaning: OriginalSourceParameterMeaning) {
        self.lower = lower; self.upper = upper; self.meaning = meaning
    }
}
