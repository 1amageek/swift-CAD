#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Complete original normalized pcurve laws retained by their producer.
public protocol OriginalRetainedSurfaceLiftSourceReading: OriginalLiftSourceReading
    where Pcurve: OriginalRetainedCurveSourceReading,
    Pcurve.Field == OriginalExactScalarDomain, PcurveSelection == Int {}
