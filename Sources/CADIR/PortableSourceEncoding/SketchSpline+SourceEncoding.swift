import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SketchSpline`.
extension CADIR.SketchSpline: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.SketchSpline", fields: 4)
        try encoder.field("controlPoints", controlPoints)
        try encoder.field("degree", degree)
        try encoder.field("isClosed", isClosed)
        try encoder.field("knots", knots)
    }
}
