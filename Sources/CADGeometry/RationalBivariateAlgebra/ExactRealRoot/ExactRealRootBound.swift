#if L2_ISOLATED_VERIFICATION
import L0
import L1
#endif

public enum ExactRealRootBound<Value: Sendable>: Sendable {
    case negativeInfinity, finite(Value), positiveInfinity
}
