import CADCore

/// Source-issued native domains and independent cycles for one unwrapped t/u/v product.
public struct OriginalNativeCurveSurfaceChart: Sendable {
    public let nativeDomains: [OriginalRationalParameterDomain]
    public let curveSpanIndex: Int
    public let surfaceUSpanIndex: Int
    public let surfaceVSpanIndex: Int
    public let curveCycle: Int
    public let surfaceUCycle: Int
    public let surfaceVCycle: Int
    public let curveTranslation: Double
    public let surfaceUTranslation: Double
    public let surfaceVTranslation: Double

    package init(chart: NativeCurveSurfacePointChart) {
        nativeDomains = chart.nativeDomains
        curveSpanIndex = chart.curveOwner.nativeIndex
        surfaceUSpanIndex = chart.surfaceOwner.uSpanIndex; surfaceVSpanIndex = chart.surfaceOwner.vSpanIndex
        curveCycle = chart.curveOwner.cycle
        surfaceUCycle = chart.surfaceOwner.uCycle; surfaceVCycle = chart.surfaceOwner.vCycle
        curveTranslation = chart.curveOwner.originalTranslation
        surfaceUTranslation = chart.surfaceOwner.originalUTranslation
        surfaceVTranslation = chart.surfaceOwner.originalVTranslation
    }
}
