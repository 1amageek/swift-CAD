import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.ProfileReference`.
extension CADIR.ProfileReference: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.ProfileReference", fields: 2, using: &admission)
        try encoder.field("featureID", featureID, using: &admission)
        try encoder.field("profileIndex", profileIndex, using: &admission)
    }
}
