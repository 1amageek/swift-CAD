import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SurfaceOperationTargetReference`.
extension CADIR.SurfaceOperationTargetReference: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.SurfaceOperationTargetReference", fields: 2, using: &admission)
        try encoder.field("face", face, using: &admission)
        try encoder.field("featureID", featureID, using: &admission)
    }
}
