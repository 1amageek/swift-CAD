#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Native host refinement shared by Native and retained pcurve lifts.
public protocol OriginalLiftSourceReading: OriginalLiftGraphSourceReading
    where Surface: OriginalBSplineSourceReading, SurfaceSelection == OriginalBSplineChartSelection {}
