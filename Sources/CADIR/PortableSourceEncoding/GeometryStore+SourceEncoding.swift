import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADTopology.GeometryStore`.
extension CADTopology.GeometryStore: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADTopology.GeometryStore", fields: 2)
        try encoder.field("curves", curves)
        try encoder.field("surfaces", surfaces)
    }
}
