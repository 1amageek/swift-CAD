import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.LoftGuideReference`.
extension CADIR.LoftGuideReference: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.LoftGuideReference", fields: 1, using: &admission)
        try encoder.field("featureID", featureID, using: &admission)
    }
}
