import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.IndependentShapeTrimmingSource`.
extension CADIR.IndependentShapeTrimmingSource: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.IndependentShapeTrimmingSource", fields: 4)
        try encoder.field("agreesWithBasis", agreesWithBasis)
        try encoder.field("first", first)
        try encoder.field("preference", preference)
        try encoder.field("second", second)
    }
}
