import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADTopology.BRepRepairChange`.
extension CADTopology.BRepRepairChange: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADTopology.BRepRepairChange", fields: 8, using: &admission)
        try encoder.field("action", action, using: &admission)
        try encoder.field("affectedEntityIDs", affectedEntityIDs, using: &admission)
        try encoder.field("deletedEntityIDs", deletedEntityIDs, using: &admission)
        try encoder.field("generatedEntityIDs", generatedEntityIDs, using: &admission)
        try encoder.field("maximumDisplacement", maximumDisplacement, using: &admission)
        try encoder.field("message", message, using: &admission)
        try encoder.field("scope", scope, using: &admission)
        try encoder.field("toleranceIncrease", toleranceIncrease, using: &admission)
    }
}
