import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.Mesh`.
extension CADIR.Mesh: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.Mesh", fields: 7, using: &admission)
        try encoder.field("faceRuns", faceRuns, using: &admission)
        try encoder.field("indices", indices, using: &admission)
        try encoder.field("material", material, using: &admission)
        try encoder.field("normals", normals, using: &admission)
        try encoder.field("positions", positions, using: &admission)
        try encoder.field("textureCoordinates", textureCoordinates, using: &admission)
        try encoder.field("vertexColors", vertexColors, using: &admission)
    }
}
