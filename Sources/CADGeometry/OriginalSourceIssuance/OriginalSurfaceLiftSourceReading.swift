#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Original Native pcurve capability, preserving its existing bindings and chart keys.
public protocol OriginalSurfaceLiftSourceReading: OriginalLiftSourceReading
    where Pcurve: OriginalBSplineSourceReading, PcurveSelection == OriginalBSplineChartSelection {}
