import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SurfaceControlLayout`.
extension CADIR.SurfaceControlLayout: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.SurfaceControlLayout", fields: 4)
        try encoder.field("uDegree", uDegree)
        try encoder.field("uSpans", uSpans)
        try encoder.field("vDegree", vDegree)
        try encoder.field("vSpans", vSpans)
    }
}
