import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.CADDocumentSourceFingerprint`.
extension CADIR.CADDocumentSourceFingerprint: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.CADDocumentSourceFingerprint", fields: 2, using: &admission)
        try encoder.field("algorithm", algorithm, using: &admission)
        try encoder.field("value", value, using: &admission)
    }
}
