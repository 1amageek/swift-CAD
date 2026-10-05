import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.JoinBodiesTargetReference`.
extension CADIR.JoinBodiesTargetReference: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.JoinBodiesTargetReference", fields: 2)
        try encoder.field("featureID", featureID)
        try encoder.field("placement", placement)
    }
}
