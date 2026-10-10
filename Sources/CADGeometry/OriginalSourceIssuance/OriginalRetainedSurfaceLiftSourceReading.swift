#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Native hosting surface with complete retained normalized pcurve laws.
public protocol OriginalRetainedSurfaceLiftSourceReading: OriginalLiftSourceReading,
    OriginalRetainedPcurveLiftSourceReading {}
