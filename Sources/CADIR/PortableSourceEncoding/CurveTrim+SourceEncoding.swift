import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADTopology.CurveTrim`.
extension CADTopology.CurveTrim: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADTopology.CurveTrim", fields: 2)
        try encoder.field("endParameter", endParameter)
        try encoder.field("startParameter", startParameter)
    }
}
