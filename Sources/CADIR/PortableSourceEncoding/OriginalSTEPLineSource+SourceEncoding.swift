import CADCore
import CADGeometry

/// Encodes the original STEP line law and its named source records.
extension OriginalSTEPLineSource: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.OriginalSTEPLineSource", fields: 8, using: &admission)
        try encoder.field("location", location, using: &admission)
        try encoder.field("direction", direction, using: &admission)
        try encoder.field("vectorID", vectorID, using: &admission)
        try encoder.field("vectorName", vectorName, using: &admission)
        try encoder.field("magnitude", magnitude, using: &admission)
        try encoder.field("lengthUnit", lengthUnit, using: &admission)
        try encoder.field("originalLengthSource", originalLengthSource, using: &admission)
        try encoder.field("adjustments", adjustments, using: &admission)
    }
}
