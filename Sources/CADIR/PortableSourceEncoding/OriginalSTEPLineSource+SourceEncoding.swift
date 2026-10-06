import CADCore
import CADGeometry

/// Encodes the original STEP line law and its named source records.
extension OriginalSTEPLineSource: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.OriginalSTEPLineSource", fields: 8)
        try encoder.field("location", location)
        try encoder.field("direction", direction)
        try encoder.field("vectorID", vectorID)
        try encoder.field("vectorName", vectorName)
        try encoder.field("magnitude", magnitude)
        try encoder.field("lengthUnit", lengthUnit)
        try encoder.field("originalLengthSource", originalLengthSource)
        try encoder.field("adjustments", adjustments)
    }
}
