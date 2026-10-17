import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.FeatureInput`.
extension CADIR.FeatureInput: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.FeatureInput", fields: 2, using: &admission)
        try encoder.field("featureID", featureID, using: &admission)
        try encoder.field("role", role, using: &admission)
    }
}
