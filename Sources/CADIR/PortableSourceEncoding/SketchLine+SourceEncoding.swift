import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SketchLine`.
extension CADIR.SketchLine: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.SketchLine", fields: 2)
        try encoder.field("end", end)
        try encoder.field("start", start)
    }
}
