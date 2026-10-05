import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SketchArc`.
extension CADIR.SketchArc: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.SketchArc", fields: 4)
        try encoder.field("center", center)
        try encoder.field("endAngle", endAngle)
        try encoder.field("radius", radius)
        try encoder.field("startAngle", startAngle)
    }
}
