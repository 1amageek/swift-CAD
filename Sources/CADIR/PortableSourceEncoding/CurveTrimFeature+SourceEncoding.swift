import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.CurveTrimFeature`.
extension CADIR.CurveTrimFeature: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.CurveTrimFeature", fields: 2)
        try encoder.field("domain", domain)
        try encoder.field("source", source)
    }
}
