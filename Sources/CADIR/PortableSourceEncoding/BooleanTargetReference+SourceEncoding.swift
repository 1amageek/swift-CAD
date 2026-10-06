import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.BooleanTargetReference`.
extension CADIR.BooleanTargetReference: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.BooleanTargetReference", fields: 2)
        try encoder.field("featureID", featureID)
        try encoder.field("placement", placement)
    }
}
