import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.BooleanTargetReference`.
extension CADIR.BooleanTargetReference: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.BooleanTargetReference", fields: 2, using: &admission)
        try encoder.field("featureID", featureID, using: &admission)
        try encoder.field("placement", placement, using: &admission)
    }
}
