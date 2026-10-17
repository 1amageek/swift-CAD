import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SurfaceControlPointReference`.
extension CADIR.SurfaceControlPointReference: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.SurfaceControlPointReference", fields: 3, using: &admission)
        try encoder.field("surface", surface, using: &admission)
        try encoder.field("uIndex", uIndex, using: &admission)
        try encoder.field("vIndex", vIndex, using: &admission)
    }
}
