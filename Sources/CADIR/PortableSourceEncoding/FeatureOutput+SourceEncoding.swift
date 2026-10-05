import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.FeatureOutput`.
extension CADIR.FeatureOutput: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.FeatureOutput", fields: 1)
        try encoder.field("role", role)
    }
}
