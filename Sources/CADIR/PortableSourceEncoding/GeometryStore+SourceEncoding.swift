import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADTopology.GeometryStore`.
extension CADTopology.GeometryStore: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADTopology.GeometryStore", fields: 2, using: &admission)
        try encoder.field("curves", curves, using: &admission)
        try encoder.field("surfaces", surfaces, using: &admission)
    }
}
