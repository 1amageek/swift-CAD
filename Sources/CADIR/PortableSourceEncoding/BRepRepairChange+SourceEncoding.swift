import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADTopology.BRepRepairChange`.
extension CADTopology.BRepRepairChange: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADTopology.BRepRepairChange", fields: 8)
        try encoder.field("action", action)
        try encoder.field("affectedEntityIDs", affectedEntityIDs)
        try encoder.field("deletedEntityIDs", deletedEntityIDs)
        try encoder.field("generatedEntityIDs", generatedEntityIDs)
        try encoder.field("maximumDisplacement", maximumDisplacement)
        try encoder.field("message", message)
        try encoder.field("scope", scope)
        try encoder.field("toleranceIncrease", toleranceIncrease)
    }
}
