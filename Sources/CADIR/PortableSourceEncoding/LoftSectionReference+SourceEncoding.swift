import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.LoftSectionReference`.
extension CADIR.LoftSectionReference: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.LoftSectionReference", fields: 7, using: &admission)
        try encoder.field("continuity", continuity, using: &admission)
        try encoder.field("faceContinuity", faceContinuity, using: &admission)
        try encoder.field("profileDirection", profileDirection, using: &admission)
        try encoder.field("section", section, using: &admission)
        try encoder.field("smoothTangentMode", smoothTangentMode, using: &admission)
        try encoder.field("smoothTangentScale", smoothTangentScale, using: &admission)
        try encoder.field("startSampleIndex", startSampleIndex, using: &admission)
    }
}
