import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.UnjoinBodyFeature`.
extension CADIR.UnjoinBodyFeature: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.UnjoinBodyFeature", fields: 1)
        try encoder.field("target", target)
    }
}
