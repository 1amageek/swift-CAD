import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.OriginalParameterGain.Product`.
extension CADGeometry.OriginalParameterGain.Product: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADGeometry.OriginalParameterGain.Product", fields: 1, using: &admission)
        try encoder.field("factors", factors, using: &admission)
    }
}
