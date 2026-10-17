import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.RevolveFeature`.
extension CADIR.RevolveFeature: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.RevolveFeature", fields: 8, using: &admission)
        try encoder.field("angle", angle, using: &admission)
        try encoder.field("axis", axis, using: &admission)
        try encoder.field("keepTools", keepTools, using: &admission)
        try encoder.field("operation", operation, using: &admission)
        try encoder.field("resultKind", resultKind, using: &admission)
        try encoder.field("section", section, using: &admission)
        try encoder.field("targets", targets, using: &admission)
        try encoder.field("thickness", thickness, using: &admission)
    }
}
