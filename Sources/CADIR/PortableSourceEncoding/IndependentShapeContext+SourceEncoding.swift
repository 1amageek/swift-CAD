import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.IndependentShapeContext`.
extension CADIR.IndependentShapeContext: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.IndependentShapeContext", fields: 6, using: &admission)
        try encoder.field("id", id, using: &admission)
        try encoder.field("identifier", identifier, using: &admission)
        try encoder.field("originalAngularSource", originalAngularSource, using: &admission)
        try encoder.field("type", type, using: &admission)
        try encoder.field("units", units, using: &admission)
        try encoder.field("originalLengthSource", originalLengthSource, using: &admission)
    }
}
