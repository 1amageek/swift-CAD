import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.IndependentShapeGroup`.
extension CADIR.IndependentShapeGroup: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.IndependentShapeGroup", fields: 7)
        try encoder.field("backPointerMembers", backPointerMembers)
        try encoder.field("description", description)
        try encoder.field("family", family)
        try encoder.field("id", id)
        try encoder.field("members", members)
        try encoder.field("name", name)
        try encoder.field("originalSTEPGroupID", originalSTEPGroupID)
    }
}
