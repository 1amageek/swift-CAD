import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.IndependentShapeRepresentation`.
extension CADIR.IndependentShapeRepresentation: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.IndependentShapeRepresentation", fields: 5)
        try encoder.field("contextID", contextID)
        try encoder.field("family", family)
        try encoder.field("id", id)
        try encoder.field("members", members)
        try encoder.field("name", name)
    }
}
