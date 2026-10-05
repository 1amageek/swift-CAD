import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.Mesh`.
extension CADIR.Mesh: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.Mesh", fields: 7)
        try encoder.field("faceRuns", faceRuns)
        try encoder.field("indices", indices)
        try encoder.field("material", material)
        try encoder.field("normals", normals)
        try encoder.field("positions", positions)
        try encoder.field("textureCoordinates", textureCoordinates)
        try encoder.field("vertexColors", vertexColors)
    }
}
