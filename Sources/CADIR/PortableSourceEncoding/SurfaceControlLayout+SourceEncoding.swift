import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SurfaceControlLayout`.
extension CADIR.SurfaceControlLayout: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.SurfaceControlLayout", fields: 4, using: &admission)
        try encoder.field("uDegree", uDegree, using: &admission)
        try encoder.field("uSpans", uSpans, using: &admission)
        try encoder.field("vDegree", vDegree, using: &admission)
        try encoder.field("vSpans", vSpans, using: &admission)
    }
}
