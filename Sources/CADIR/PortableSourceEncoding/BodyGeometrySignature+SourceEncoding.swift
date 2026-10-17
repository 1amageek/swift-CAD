import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.BodyGeometrySignature`.
extension CADIR.BodyGeometrySignature: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.BodyGeometrySignature", fields: 2, using: &admission)
        try encoder.field("kind", kind, using: &admission)
        try encoder.field("shells", shells, using: &admission)
    }
}
