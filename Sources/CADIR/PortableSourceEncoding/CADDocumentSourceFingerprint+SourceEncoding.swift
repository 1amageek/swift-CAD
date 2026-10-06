import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.CADDocumentSourceFingerprint`.
extension CADIR.CADDocumentSourceFingerprint: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.CADDocumentSourceFingerprint", fields: 2)
        try encoder.field("algorithm", algorithm)
        try encoder.field("value", value)
    }
}
