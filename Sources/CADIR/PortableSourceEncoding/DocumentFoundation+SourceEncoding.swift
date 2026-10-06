import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.DocumentFoundation`.
extension CADIR.DocumentFoundation: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.DocumentFoundation", fields: 1)
        try encoder.field("attributes", attributes)
    }
}
