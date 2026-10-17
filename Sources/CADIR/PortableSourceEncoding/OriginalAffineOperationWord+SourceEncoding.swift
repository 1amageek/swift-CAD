import CADCore
import CADGeometry

/// Encodes original source fields; prepared geometry remains derived.
extension OriginalAffineOperationWord: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADGeometry.OriginalAffineOperationWord", fields: 1, using: &admission)
        try encoder.field("factors", factors, using: &admission)
    }
}
