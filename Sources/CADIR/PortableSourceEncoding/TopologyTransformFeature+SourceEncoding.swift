import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.TopologyTransformFeature`.
extension CADIR.TopologyTransformFeature: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.TopologyTransformFeature", fields: 3)
        try encoder.field("motion", motion)
        try encoder.field("subshapes", subshapes)
        try encoder.field("target", target)
    }
}
