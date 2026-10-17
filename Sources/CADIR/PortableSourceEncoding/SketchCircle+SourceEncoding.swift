import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SketchCircle`.
extension CADIR.SketchCircle: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.SketchCircle", fields: 2, using: &admission)
        try encoder.field("center", center, using: &admission)
        try encoder.field("radius", radius, using: &admission)
    }
}
