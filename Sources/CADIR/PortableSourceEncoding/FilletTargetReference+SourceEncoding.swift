import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.FilletTargetReference`.
extension CADIR.FilletTargetReference: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.FilletTargetReference", fields: 1, using: &admission)
        try encoder.field("featureID", featureID, using: &admission)
    }
}
