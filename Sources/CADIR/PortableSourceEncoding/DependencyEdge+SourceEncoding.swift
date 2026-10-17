import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.DependencyEdge`.
extension CADIR.DependencyEdge: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.DependencyEdge", fields: 2, using: &admission)
        try encoder.field("source", source, using: &admission)
        try encoder.field("target", target, using: &admission)
    }
}
