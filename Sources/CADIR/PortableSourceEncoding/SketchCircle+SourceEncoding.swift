import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SketchCircle`.
extension CADIR.SketchCircle: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.SketchCircle", fields: 2)
        try encoder.field("center", center)
        try encoder.field("radius", radius)
    }
}
