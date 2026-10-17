import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SketchPoint`.
extension CADIR.SketchPoint: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.SketchPoint", fields: 2, using: &admission)
        try encoder.field("x", x, using: &admission)
        try encoder.field("y", y, using: &admission)
    }
}
