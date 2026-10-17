import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.IsoparamFeature`.
extension CADIR.IsoparamFeature: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.IsoparamFeature", fields: 5, using: &admission)
        try encoder.field("direction", direction, using: &admission)
        try encoder.field("face", face, using: &admission)
        try encoder.field("fractions", fractions, using: &admission)
        try encoder.field("subdividesControlNet", subdividesControlNet, using: &admission)
        try encoder.field("target", target, using: &admission)
    }
}
