import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SweepGuideReference`.
extension CADIR.SweepGuideReference: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.SweepGuideReference", fields: 1)
        try encoder.field("featureID", featureID)
    }
}
