import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.EdgeBlendLimits`.
extension CADIR.EdgeBlendLimits: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.EdgeBlendLimits", fields: 3)
        try encoder.field("end", end)
        try encoder.field("reversed", reversed)
        try encoder.field("start", start)
    }
}
