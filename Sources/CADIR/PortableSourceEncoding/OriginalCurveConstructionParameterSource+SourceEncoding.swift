import CADCore
import CADGeometry

extension OriginalCurveConstructionParameterSource: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADGeometry.OriginalCurveConstructionParameterSource", fields: 6)
        try encoder.field("endParameter", endParameter)
        try encoder.field("firstFraction", firstFraction)
        try encoder.field("lastFraction", lastFraction)
        try encoder.field("law", law)
        try encoder.field("source", source)
        try encoder.field("startParameter", startParameter)
    }
}
