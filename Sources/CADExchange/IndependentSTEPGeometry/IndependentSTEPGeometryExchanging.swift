public protocol IndependentSTEPGeometryExchanging: Sendable {
    func writeIndependentGeometry(_ model: IndependentSTEPGeometry, to sink: any ByteSink) throws
    func importIndependentGeometry(_ source: any ByteSource) throws -> IndependentSTEPGeometry
}
