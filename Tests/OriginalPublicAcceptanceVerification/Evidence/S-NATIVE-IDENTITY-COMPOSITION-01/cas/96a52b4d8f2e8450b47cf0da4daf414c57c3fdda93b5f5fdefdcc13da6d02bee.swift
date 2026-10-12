#if L2_ISOLATED_VERIFICATION
import L0
import L1
#endif

public enum ExactRealRootClassification: Sendable, Equatable {
    case finite(distinct: Int, totalMultiplicity: Int)
    case wholeDomain
}
