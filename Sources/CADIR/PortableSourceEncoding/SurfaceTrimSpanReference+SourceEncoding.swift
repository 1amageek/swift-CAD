import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SurfaceTrimSpanReference`.
extension CADIR.SurfaceTrimSpanReference: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.SurfaceTrimSpanReference", fields: 2, using: &admission)
        try encoder.field("spanIndex", spanIndex, using: &admission)
        try encoder.field("trim", trim, using: &admission)
    }
}
