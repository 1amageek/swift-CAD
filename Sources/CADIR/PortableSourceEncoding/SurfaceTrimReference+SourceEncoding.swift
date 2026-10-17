import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SurfaceTrimReference`.
extension CADIR.SurfaceTrimReference: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.SurfaceTrimReference", fields: 3, using: &admission)
        try encoder.field("edgeIndex", edgeIndex, using: &admission)
        try encoder.field("loopIndex", loopIndex, using: &admission)
        try encoder.field("surface", surface, using: &admission)
    }
}
