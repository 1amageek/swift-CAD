import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.EdgeMoveFeature`.
extension CADIR.EdgeMoveFeature: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.EdgeMoveFeature", fields: 3)
        try encoder.field("edge", edge)
        try encoder.field("target", target)
        try encoder.field("translation", translation)
    }
}
