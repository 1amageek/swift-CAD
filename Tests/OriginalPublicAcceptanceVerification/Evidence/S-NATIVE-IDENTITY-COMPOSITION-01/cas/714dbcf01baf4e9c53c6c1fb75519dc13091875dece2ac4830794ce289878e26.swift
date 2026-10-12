#if L2_ISOLATED_VERIFICATION
import L0
import L1
import DI0
#endif

/// Public L2 spelling; the conversion preserves every tagged bound exactly.
public enum ExactRealRootBound<Value: Sendable>: Sendable {
    case negativeInfinity, finite(Value), positiveInfinity
    var domainBound: ExactParameterBound<Value> {
        switch self {
        case .negativeInfinity: return .negativeInfinity
        case .positiveInfinity: return .positiveInfinity
        case .finite(let value): return .finite(value)
        }
    }
    init(_ source: ExactParameterBound<Value>) {
        switch source {
        case .negativeInfinity: self = .negativeInfinity
        case .positiveInfinity: self = .positiveInfinity
        case .finite(let value): self = .finite(value)
        }
    }
}
