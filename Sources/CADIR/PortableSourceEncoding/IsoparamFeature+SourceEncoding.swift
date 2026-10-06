import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.IsoparamFeature`.
extension CADIR.IsoparamFeature: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.IsoparamFeature", fields: 5)
        try encoder.field("direction", direction)
        try encoder.field("face", face)
        try encoder.field("fractions", fractions)
        try encoder.field("subdividesControlNet", subdividesControlNet)
        try encoder.field("target", target)
    }
}
