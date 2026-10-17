import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.ThickenFeature`.
extension CADIR.ThickenFeature: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.ThickenFeature", fields: 3, using: &admission)
        try encoder.field("back", back, using: &admission)
        try encoder.field("front", front, using: &admission)
        try encoder.field("target", target, using: &admission)
    }
}
