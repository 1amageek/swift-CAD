import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.ProfileReference`.
extension CADIR.ProfileReference: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.ProfileReference", fields: 2)
        try encoder.field("featureID", featureID)
        try encoder.field("profileIndex", profileIndex)
    }
}
