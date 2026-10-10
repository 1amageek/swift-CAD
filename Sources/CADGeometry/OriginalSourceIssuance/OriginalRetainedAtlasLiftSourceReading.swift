#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Both children retain their complete original producer charts.
public protocol OriginalRetainedAtlasLiftSourceReading: OriginalRetainedPcurveLiftSourceReading
    where Surface: OriginalRetainedSurfaceSourceReading,
    Surface.Field == OriginalExactScalarDomain, SurfaceSelection == Int {}
