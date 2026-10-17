import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.TopologyTransformFeature`.
extension CADIR.TopologyTransformFeature: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.TopologyTransformFeature", fields: 3, using: &admission)
        try encoder.field("motion", motion, using: &admission)
        try encoder.field("subshapes", subshapes, using: &admission)
        try encoder.field("target", target, using: &admission)
    }
}
