import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.IndependentShapeContext`.
extension CADIR.IndependentShapeContext: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.IndependentShapeContext", fields: 6)
        try encoder.field("id", id)
        try encoder.field("identifier", identifier)
        try encoder.field("originalAngularSource", originalAngularSource)
        try encoder.field("type", type)
        try encoder.field("units", units)
        try encoder.field("originalLengthSource", originalLengthSource)
    }
}
