import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.DependencyEdge`.
extension CADIR.DependencyEdge: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.DependencyEdge", fields: 2)
        try encoder.field("source", source)
        try encoder.field("target", target)
    }
}
