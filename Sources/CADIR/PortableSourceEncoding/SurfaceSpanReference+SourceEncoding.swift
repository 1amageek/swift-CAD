import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SurfaceSpanReference`.
extension CADIR.SurfaceSpanReference: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.SurfaceSpanReference", fields: 3, using: &admission)
        try encoder.field("direction", direction, using: &admission)
        try encoder.field("spanIndex", spanIndex, using: &admission)
        try encoder.field("surface", surface, using: &admission)
    }
}
