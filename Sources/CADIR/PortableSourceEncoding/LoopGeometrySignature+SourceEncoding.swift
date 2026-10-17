import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.LoopGeometrySignature`.
extension CADIR.LoopGeometrySignature: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.LoopGeometrySignature", fields: 2, using: &admission)
        try encoder.field("coedges", coedges, using: &admission)
        try encoder.field("role", role, using: &admission)
    }
}
