#if EXACT_DOMAIN_ISOLATED_VERIFICATION
import L0
#endif

public enum ExactParameterBound<Value: Sendable>: Sendable {
    case negativeInfinity, finite(Value), positiveInfinity
}
