import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.IndependentShapeTrimmingSource`.
extension CADIR.IndependentShapeTrimmingSource: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.IndependentShapeTrimmingSource", fields: 4, using: &admission)
        try encoder.field("agreesWithBasis", agreesWithBasis, using: &admission)
        try encoder.field("first", first, using: &admission)
        try encoder.field("preference", preference, using: &admission)
        try encoder.field("second", second, using: &admission)
    }
}
