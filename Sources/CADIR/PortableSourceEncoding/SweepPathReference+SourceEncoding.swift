import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SweepPathReference`.
extension CADIR.SweepPathReference: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.SweepPathReference", fields: 1)
        try encoder.field("featureID", featureID)
    }
}
