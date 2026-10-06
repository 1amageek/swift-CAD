public struct ExchangeGeometryWriteReport: Sendable {
    public let preservation: ExchangePreservationReport
    public let curveConversions: [ExchangeCurveConversionGuarantee]
    public let surfaceConversions: [ExchangeSurfaceConversionGuarantee]
    public init(preservation: ExchangePreservationReport, surfaceConversions: [ExchangeSurfaceConversionGuarantee],
        curveConversions: [ExchangeCurveConversionGuarantee] = []) {
        self.preservation = preservation
        self.curveConversions = curveConversions
        self.surfaceConversions = surfaceConversions
    }
}
