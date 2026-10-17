import CADCore
import CADGeometry

extension OriginalCurveConstructionParameterSource: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADGeometry.OriginalCurveConstructionParameterSource", fields: 6, using: &admission)
        try encoder.field("endParameter", endParameter, using: &admission)
        try encoder.field("firstFraction", firstFraction, using: &admission)
        try encoder.field("lastFraction", lastFraction, using: &admission)
        try encoder.field("law", law, using: &admission)
        try encoder.field("source", source, using: &admission)
        try encoder.field("startParameter", startParameter, using: &admission)
    }
}
