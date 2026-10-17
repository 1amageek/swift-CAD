import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADTopology.CurveTrim`.
extension CADTopology.CurveTrim: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADTopology.CurveTrim", fields: 2, using: &admission)
        try encoder.field("endParameter", endParameter, using: &admission)
        try encoder.field("startParameter", startParameter, using: &admission)
    }
}
