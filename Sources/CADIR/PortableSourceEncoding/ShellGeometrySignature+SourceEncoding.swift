import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.ShellGeometrySignature`.
extension CADIR.ShellGeometrySignature: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.ShellGeometrySignature", fields: 2, using: &admission)
        try encoder.field("faces", faces, using: &admission)
        try encoder.field("orientation", orientation, using: &admission)
    }
}
