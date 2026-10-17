import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.FeatureOutput`.
extension CADIR.FeatureOutput: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.FeatureOutput", fields: 1, using: &admission)
        try encoder.field("role", role, using: &admission)
    }
}
