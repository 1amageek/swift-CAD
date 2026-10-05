import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.RevolveFeature`.
extension CADIR.RevolveFeature: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.RevolveFeature", fields: 8)
        try encoder.field("angle", angle)
        try encoder.field("axis", axis)
        try encoder.field("keepTools", keepTools)
        try encoder.field("operation", operation)
        try encoder.field("resultKind", resultKind)
        try encoder.field("section", section)
        try encoder.field("targets", targets)
        try encoder.field("thickness", thickness)
    }
}
