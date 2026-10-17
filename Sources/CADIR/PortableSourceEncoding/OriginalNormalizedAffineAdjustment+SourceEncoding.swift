import CADCore
import CADGeometry

/// Encodes original source fields; prepared geometry remains derived.
extension OriginalNormalizedAffineAdjustment: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADGeometry.OriginalNormalizedAffineAdjustment", fields: 2, using: &admission)
        try encoder.field("conjugates", conjugates, using: &admission)
        try encoder.field("displacement", displacement, using: &admission)
    }
}
