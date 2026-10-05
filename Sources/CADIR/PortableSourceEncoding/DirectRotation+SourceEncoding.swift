import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.DirectRotation`.
extension CADIR.DirectRotation: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.DirectRotation", fields: 3)
        try encoder.field("angle", angle)
        try encoder.field("axis", axis)
        try encoder.field("origin", origin)
    }
}
