import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.IndependentShapeAngularSource`.
extension CADIR.IndependentShapeAngularSource: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.IndependentShapeAngularSource", fields: 2)
        try encoder.field("id", id)
        try encoder.field("law", law)
    }
}
