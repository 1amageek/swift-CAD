import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.G2BlendTargetReference`.
extension CADIR.G2BlendTargetReference: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.G2BlendTargetReference", fields: 1)
        try encoder.field("featureID", featureID)
    }
}
