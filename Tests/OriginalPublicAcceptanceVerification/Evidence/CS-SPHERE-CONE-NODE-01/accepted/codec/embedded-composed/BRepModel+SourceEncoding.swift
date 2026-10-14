import CADCore
import CADTopology

/// Encodes original source fields owned by `CADTopology.BRepModel`.
extension CADTopology.BRepModel: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADTopology.BRepModel", fields: 7)
        try encoder.field("bodies", bodies)
        try encoder.field("edges", edges)
        try encoder.field("faces", faces)
        try encoder.field("geometry", geometry)
        try encoder.field("loops", loops)
        try encoder.field("shells", shells)
        try encoder.field("vertices", vertices)
    }
}
