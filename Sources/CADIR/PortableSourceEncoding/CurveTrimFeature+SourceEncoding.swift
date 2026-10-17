import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.CurveTrimFeature`.
extension CADIR.CurveTrimFeature: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.CurveTrimFeature", fields: 2, using: &admission)
        try encoder.field("domain", domain, using: &admission)
        try encoder.field("source", source, using: &admission)
    }
}
