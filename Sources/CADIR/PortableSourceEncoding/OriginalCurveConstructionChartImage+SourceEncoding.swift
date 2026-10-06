import CADCore
import CADGeometry

extension OriginalCurveConstructionChartImage: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADGeometry.OriginalCurveConstructionChartImage", fields: 2)
        try encoder.field("certificationTolerance", certificationTolerance)
        try encoder.field("chart", chart)
    }
}
