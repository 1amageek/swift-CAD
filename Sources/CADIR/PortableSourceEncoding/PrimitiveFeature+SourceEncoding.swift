import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.PrimitiveFeature`.
extension CADIR.PrimitiveFeature: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.PrimitiveFeature", fields: 1)
        try encoder.field("definition", definition)
    }
}
