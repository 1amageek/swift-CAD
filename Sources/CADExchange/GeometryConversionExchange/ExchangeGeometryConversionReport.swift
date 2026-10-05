public struct ExchangeGeometryConversionReport: Sendable {
    public let curveConversions: [ExchangeCurveConversionGuarantee]
    public let surfaceConversions: [ExchangeSurfaceConversionGuarantee]
    public init(curveConversions: [ExchangeCurveConversionGuarantee], surfaceConversions: [ExchangeSurfaceConversionGuarantee]) {
        self.curveConversions = curveConversions
        self.surfaceConversions = surfaceConversions
    }
}
