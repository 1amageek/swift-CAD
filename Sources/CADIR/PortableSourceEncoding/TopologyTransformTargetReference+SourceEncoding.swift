import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.TopologyTransformTargetReference`.
extension CADIR.TopologyTransformTargetReference: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.TopologyTransformTargetReference", fields: 1)
        try encoder.field("featureID", featureID)
    }
}
