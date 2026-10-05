import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.ThickenFeature`.
extension CADIR.ThickenFeature: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.ThickenFeature", fields: 3)
        try encoder.field("back", back)
        try encoder.field("front", front)
        try encoder.field("target", target)
    }
}
