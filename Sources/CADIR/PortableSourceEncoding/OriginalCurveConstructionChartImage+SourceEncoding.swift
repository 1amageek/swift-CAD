import CADCore
import CADGeometry

extension OriginalCurveConstructionChartImage: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADGeometry.OriginalCurveConstructionChartImage", fields: 2, using: &admission)
        try encoder.field("certificationTolerance", certificationTolerance, using: &admission)
        try encoder.field("chart", chart, using: &admission)
    }
}
