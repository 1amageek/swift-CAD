import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.ThickenTargetReference`.
extension CADIR.ThickenTargetReference: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.ThickenTargetReference", fields: 1)
        try encoder.field("featureID", featureID)
    }
}
