import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.LoftSectionReference`.
extension CADIR.LoftSectionReference: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.LoftSectionReference", fields: 7)
        try encoder.field("continuity", continuity)
        try encoder.field("faceContinuity", faceContinuity)
        try encoder.field("profileDirection", profileDirection)
        try encoder.field("section", section)
        try encoder.field("smoothTangentMode", smoothTangentMode)
        try encoder.field("smoothTangentScale", smoothTangentScale)
        try encoder.field("startSampleIndex", startSampleIndex)
    }
}
