import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.DocumentObjectReference`.
extension CADIR.DocumentObjectReference: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.DocumentObjectReference", fields: 2)
        try encoder.field("documentID", documentID)
        try encoder.field("target", target)
    }
}
