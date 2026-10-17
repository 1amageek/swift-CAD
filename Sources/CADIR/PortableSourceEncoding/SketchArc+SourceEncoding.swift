import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SketchArc`.
extension CADIR.SketchArc: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.SketchArc", fields: 4, using: &admission)
        try encoder.field("center", center, using: &admission)
        try encoder.field("endAngle", endAngle, using: &admission)
        try encoder.field("radius", radius, using: &admission)
        try encoder.field("startAngle", startAngle, using: &admission)
    }
}
