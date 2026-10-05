import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.BooleanToolReference`.
extension CADIR.BooleanToolReference: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.BooleanToolReference", fields: 2)
        try encoder.field("featureID", featureID)
        try encoder.field("placement", placement)
    }
}
