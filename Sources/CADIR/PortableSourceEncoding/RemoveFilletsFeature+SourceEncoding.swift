import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.RemoveFilletsFeature`.
extension CADIR.RemoveFilletsFeature: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.RemoveFilletsFeature", fields: 3, using: &admission)
        try encoder.field("convexity", convexity, using: &admission)
        try encoder.field("maximumRadius", maximumRadius, using: &admission)
        try encoder.field("target", target, using: &admission)
    }
}
