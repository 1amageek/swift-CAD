import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.IndependentShapeGroup`.
extension CADIR.IndependentShapeGroup: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.IndependentShapeGroup", fields: 7, using: &admission)
        try encoder.field("backPointerMembers", backPointerMembers, using: &admission)
        try encoder.field("description", description, using: &admission)
        try encoder.field("family", family, using: &admission)
        try encoder.field("id", id, using: &admission)
        try encoder.field("members", members, using: &admission)
        try encoder.field("name", name, using: &admission)
        try encoder.field("originalSTEPGroupID", originalSTEPGroupID, using: &admission)
    }
}
