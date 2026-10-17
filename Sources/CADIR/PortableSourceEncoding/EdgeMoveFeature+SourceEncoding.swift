import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.EdgeMoveFeature`.
extension CADIR.EdgeMoveFeature: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.EdgeMoveFeature", fields: 3, using: &admission)
        try encoder.field("edge", edge, using: &admission)
        try encoder.field("target", target, using: &admission)
        try encoder.field("translation", translation, using: &admission)
    }
}
