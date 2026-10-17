import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.ExtrudeFeature`.
extension CADIR.ExtrudeFeature: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.ExtrudeFeature", fields: 11, using: &admission)
        try encoder.field("direction", direction, using: &admission)
        try encoder.field("distance", distance, using: &admission)
        try encoder.field("draftAngle", draftAngle, using: &admission)
        try encoder.field("draftDirection", draftDirection, using: &admission)
        try encoder.field("keepTools", keepTools, using: &admission)
        try encoder.field("operation", operation, using: &admission)
        try encoder.field("resultKind", resultKind, using: &admission)
        try encoder.field("section", section, using: &admission)
        try encoder.field("startDistance", startDistance, using: &admission)
        try encoder.field("targets", targets, using: &admission)
        try encoder.field("thickness", thickness, using: &admission)
    }
}
