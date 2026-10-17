import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.IndependentShapeRepresentation`.
extension CADIR.IndependentShapeRepresentation: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.IndependentShapeRepresentation", fields: 5, using: &admission)
        try encoder.field("contextID", contextID, using: &admission)
        try encoder.field("family", family, using: &admission)
        try encoder.field("id", id, using: &admission)
        try encoder.field("members", members, using: &admission)
        try encoder.field("name", name, using: &admission)
    }
}
