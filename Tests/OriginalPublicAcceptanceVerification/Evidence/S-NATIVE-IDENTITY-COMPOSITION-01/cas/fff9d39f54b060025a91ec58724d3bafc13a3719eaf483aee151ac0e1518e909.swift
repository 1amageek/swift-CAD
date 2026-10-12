#if L3_ISOLATED_VERIFICATION
import L0
import L1
import L2
#endif

public enum ExactRealCellSignRelation: Sendable {
    case equal, notEqual, less, lessOrEqual, greater, greaterOrEqual
    func accepts(_ sign: ExactSign) -> Bool {
        switch self {
        case .equal: return sign == .zero
        case .notEqual: return sign != .zero
        case .less: return sign == .negative
        case .lessOrEqual: return sign != .positive
        case .greater: return sign == .positive
        case .greaterOrEqual: return sign != .negative
        }
    }
}
