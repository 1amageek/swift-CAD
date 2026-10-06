import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SurfaceOperationTargetReference`.
extension CADIR.SurfaceOperationTargetReference: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.SurfaceOperationTargetReference", fields: 2)
        try encoder.field("face", face)
        try encoder.field("featureID", featureID)
    }
}
