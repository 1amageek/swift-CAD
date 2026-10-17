import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.CurvePatchFeature`.
extension CADIR.CurvePatchFeature: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.CurvePatchFeature", fields: 1, using: &admission)
        try encoder.field("curves", curves, using: &admission)
    }
}
