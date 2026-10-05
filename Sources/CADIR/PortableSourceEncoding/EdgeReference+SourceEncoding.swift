import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.EdgeReference`.
extension CADIR.EdgeReference: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.EdgeReference", fields: 1)
        try encoder.field("subshape", subshape)
    }
}
