import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SweepTargetReference`.
extension CADIR.SweepTargetReference: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.SweepTargetReference", fields: 1)
        try encoder.field("featureID", featureID)
    }
}
