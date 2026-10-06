import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.RemoveRedundantTopologyFeature`.
extension CADIR.RemoveRedundantTopologyFeature: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.RemoveRedundantTopologyFeature", fields: 1)
        try encoder.field("target", target)
    }
}
