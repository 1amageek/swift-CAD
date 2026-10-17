import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.RemoveRedundantTopologyFeature`.
extension CADIR.RemoveRedundantTopologyFeature: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.RemoveRedundantTopologyFeature", fields: 1, using: &admission)
        try encoder.field("target", target, using: &admission)
    }
}
