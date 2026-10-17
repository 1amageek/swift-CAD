import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.BooleanToolReference`.
extension CADIR.BooleanToolReference: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.BooleanToolReference", fields: 2, using: &admission)
        try encoder.field("featureID", featureID, using: &admission)
        try encoder.field("placement", placement, using: &admission)
    }
}
