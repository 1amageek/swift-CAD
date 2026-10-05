import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.ExtrudeFeature`.
extension CADIR.ExtrudeFeature: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.ExtrudeFeature", fields: 11)
        try encoder.field("direction", direction)
        try encoder.field("distance", distance)
        try encoder.field("draftAngle", draftAngle)
        try encoder.field("draftDirection", draftDirection)
        try encoder.field("keepTools", keepTools)
        try encoder.field("operation", operation)
        try encoder.field("resultKind", resultKind)
        try encoder.field("section", section)
        try encoder.field("startDistance", startDistance)
        try encoder.field("targets", targets)
        try encoder.field("thickness", thickness)
    }
}
