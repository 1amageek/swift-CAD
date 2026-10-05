import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.ShellGeometrySignature`.
extension CADIR.ShellGeometrySignature: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.ShellGeometrySignature", fields: 2)
        try encoder.field("faces", faces)
        try encoder.field("orientation", orientation)
    }
}
