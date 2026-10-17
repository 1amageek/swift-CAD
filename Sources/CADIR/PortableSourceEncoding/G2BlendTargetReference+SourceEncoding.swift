import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.G2BlendTargetReference`.
extension CADIR.G2BlendTargetReference: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.G2BlendTargetReference", fields: 1, using: &admission)
        try encoder.field("featureID", featureID, using: &admission)
    }
}
