#if L3_ISOLATED_VERIFICATION
import L0
import L1
import L2
#endif

public enum ExactRealCellInstruction: Sendable {
    case literal(Bool)
    case sign(polynomial: Int, relation: ExactRealCellSignRelation)
    case not, and, or
}
