#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Existing Native child capability; source bindings and chart APIs are unchanged.
public protocol OriginalRollingBallSourceReading: OriginalRollingBallChildSourceReading
    where Child: OriginalBSplineSourceReading {}
