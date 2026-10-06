import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.VertexMoveTargetReference`.
extension CADIR.VertexMoveTargetReference: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.VertexMoveTargetReference", fields: 1)
        try encoder.field("featureID", featureID)
    }
}
