import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.IndependentShapeAngularConversion`.
extension CADIR.IndependentShapeAngularConversion: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.IndependentShapeAngularConversion", fields: 8, using: &admission)
        try encoder.field("base", base, using: &admission)
        try encoder.field("dimensions", dimensions, using: &admission)
        try encoder.field("dimensionsID", dimensionsID, using: &admission)
        try encoder.field("factor", factor, using: &admission)
        try encoder.field("interpretation", interpretation, using: &admission)
        try encoder.field("measureID", measureID, using: &admission)
        try encoder.field("measureKind", measureKind, using: &admission)
        try encoder.field("name", name, using: &admission)
    }
}
