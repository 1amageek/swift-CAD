import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SketchSpline`.
extension CADIR.SketchSpline: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.SketchSpline", fields: 4, using: &admission)
        try encoder.field("controlPoints", controlPoints, using: &admission)
        try encoder.field("degree", degree, using: &admission)
        try encoder.field("isClosed", isClosed, using: &admission)
        try encoder.field("knots", knots, using: &admission)
    }
}
