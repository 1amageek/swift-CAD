import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.FilletTargetReference`.
extension CADIR.FilletTargetReference: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.FilletTargetReference", fields: 1)
        try encoder.field("featureID", featureID)
    }
}
