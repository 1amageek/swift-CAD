#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

public struct OriginalSurfaceLiftGraphEvidence<S: OriginalLiftSourceReading>: Sendable {
    public let surface: OriginalRationalChartReceipt<S.Surface,OriginalBSplineChartSelection,OriginalExactScalarDomain>
    public let pcurve: OriginalRationalChartReceipt<S.Pcurve,S.PcurveSelection,OriginalExactScalarDomain>
    public let surfaceTranslation: [OriginalExactScalar]?
    init(surface: OriginalRationalChartReceipt<S.Surface,OriginalBSplineChartSelection,OriginalExactScalarDomain>,
        pcurve: OriginalRationalChartReceipt<S.Pcurve,S.PcurveSelection,OriginalExactScalarDomain>,
        surfaceTranslation: [OriginalExactScalar]? = nil) {
        self.surface = surface; self.pcurve = pcurve; self.surfaceTranslation = surfaceTranslation
    }
}
