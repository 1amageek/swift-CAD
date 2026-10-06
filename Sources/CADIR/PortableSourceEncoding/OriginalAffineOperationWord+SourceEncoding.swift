import CADCore
import CADGeometry

/// Encodes original source fields; prepared geometry remains derived.
extension OriginalAffineOperationWord: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADGeometry.OriginalAffineOperationWord", fields: 1)
        try encoder.field("factors", factors)
    }
}
