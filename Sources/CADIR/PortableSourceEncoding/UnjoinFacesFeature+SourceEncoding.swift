import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.UnjoinFacesFeature`.
extension CADIR.UnjoinFacesFeature: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.UnjoinFacesFeature", fields: 2, using: &admission)
        try encoder.field("selection", selection, using: &admission)
        try encoder.field("target", target, using: &admission)
    }
}
