import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.JoinBodiesFeature`.
extension CADIR.JoinBodiesFeature: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.JoinBodiesFeature", fields: 2, using: &admission)
        try encoder.field("mode", mode, using: &admission)
        try encoder.field("targets", targets, using: &admission)
    }
}
