import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.EdgeMoveTargetReference`.
extension CADIR.EdgeMoveTargetReference: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.EdgeMoveTargetReference", fields: 1)
        try encoder.field("featureID", featureID)
    }
}
