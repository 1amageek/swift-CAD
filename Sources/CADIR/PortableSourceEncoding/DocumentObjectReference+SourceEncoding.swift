import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.DocumentObjectReference`.
extension CADIR.DocumentObjectReference: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.DocumentObjectReference", fields: 2, using: &admission)
        try encoder.field("documentID", documentID, using: &admission)
        try encoder.field("target", target, using: &admission)
    }
}
