#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Complete retained normalized pcurve authority for either hosting representation.
public protocol OriginalRetainedPcurveLiftSourceReading: OriginalLiftGraphSourceReading
    where Pcurve: OriginalRetainedCurveSourceReading,
    Pcurve.Field == OriginalExactScalarDomain, PcurveSelection == Int {}
