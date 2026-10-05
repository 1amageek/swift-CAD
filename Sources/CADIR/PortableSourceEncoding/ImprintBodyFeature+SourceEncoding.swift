import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.ImprintBodyFeature`.
extension CADIR.ImprintBodyFeature: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.ImprintBodyFeature", fields: 3)
        try encoder.field("completion", completion)
        try encoder.field("target", target)
        try encoder.field("tools", tools)
    }
}
