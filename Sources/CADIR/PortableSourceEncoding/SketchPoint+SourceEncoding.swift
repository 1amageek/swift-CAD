import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SketchPoint`.
extension CADIR.SketchPoint: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.SketchPoint", fields: 2)
        try encoder.field("x", x)
        try encoder.field("y", y)
    }
}
