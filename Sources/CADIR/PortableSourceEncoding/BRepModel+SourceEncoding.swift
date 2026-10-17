import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADTopology.BRepModel`.
extension CADTopology.BRepModel: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADTopology.BRepModel", fields: 7, using: &admission)
        try encoder.field("bodies", bodies, using: &admission)
        try encoder.field("edges", edges, using: &admission)
        try encoder.field("faces", faces, using: &admission)
        try encoder.field("geometry", geometry, using: &admission)
        try encoder.field("loops", loops, using: &admission)
        try encoder.field("shells", shells, using: &admission)
        try encoder.field("vertices", vertices, using: &admission)
    }
}
