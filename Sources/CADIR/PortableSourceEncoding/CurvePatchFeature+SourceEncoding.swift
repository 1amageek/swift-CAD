import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.CurvePatchFeature`.
extension CADIR.CurvePatchFeature: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.CurvePatchFeature", fields: 1)
        try encoder.field("curves", curves)
    }
}
