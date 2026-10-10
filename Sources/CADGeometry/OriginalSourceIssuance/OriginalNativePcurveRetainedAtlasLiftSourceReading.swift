#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Retained host charts and authored Native pcurve spans share one lift source.
public protocol OriginalNativePcurveRetainedAtlasLiftSourceReading: OriginalLiftGraphSourceReading
    where Surface: OriginalRetainedSurfaceSourceReading, Surface.Field == OriginalExactScalarDomain,
    SurfaceSelection == Int, Pcurve: OriginalBSplineSourceReading,
    PcurveSelection == OriginalBSplineChartSelection {}
