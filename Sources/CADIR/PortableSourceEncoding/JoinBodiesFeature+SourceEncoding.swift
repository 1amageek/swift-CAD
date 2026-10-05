import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.JoinBodiesFeature`.
extension CADIR.JoinBodiesFeature: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.JoinBodiesFeature", fields: 2)
        try encoder.field("mode", mode)
        try encoder.field("targets", targets)
    }
}
