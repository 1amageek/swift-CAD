import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.LoopGeometrySignature`.
extension CADIR.LoopGeometrySignature: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.LoopGeometrySignature", fields: 2)
        try encoder.field("coedges", coedges)
        try encoder.field("role", role)
    }
}
