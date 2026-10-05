import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.FeatureInput`.
extension CADIR.FeatureInput: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.FeatureInput", fields: 2)
        try encoder.field("featureID", featureID)
        try encoder.field("role", role)
    }
}
