import CADCore
import CADIR

public protocol CertifiedDocumentGeometryExchanging {
    func writeConverting(_ document: CADDocument, units: UnitSystem?,
        geometryPolicy: ExchangeGeometryConversionPolicy, to sink: any ByteSink) throws -> ExchangeGeometryConversionReport
}
