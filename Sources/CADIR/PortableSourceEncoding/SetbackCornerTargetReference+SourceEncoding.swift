import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SetbackCornerTargetReference`.
extension CADIR.SetbackCornerTargetReference: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.SetbackCornerTargetReference", fields: 1)
        try encoder.field("featureID", featureID)
    }
}
