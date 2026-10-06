import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.UnjoinFacesFeature`.
extension CADIR.UnjoinFacesFeature: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.UnjoinFacesFeature", fields: 2)
        try encoder.field("selection", selection)
        try encoder.field("target", target)
    }
}
