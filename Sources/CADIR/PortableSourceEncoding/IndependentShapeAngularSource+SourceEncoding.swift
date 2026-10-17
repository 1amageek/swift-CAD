import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.IndependentShapeAngularSource`.
extension CADIR.IndependentShapeAngularSource: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.IndependentShapeAngularSource", fields: 2, using: &admission)
        try encoder.field("id", id, using: &admission)
        try encoder.field("law", law, using: &admission)
    }
}
