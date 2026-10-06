import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SurfaceTrimSpanReference`.
extension CADIR.SurfaceTrimSpanReference: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.SurfaceTrimSpanReference", fields: 2)
        try encoder.field("spanIndex", spanIndex)
        try encoder.field("trim", trim)
    }
}
