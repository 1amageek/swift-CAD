import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.ImprintBodyTool`.
extension CADIR.ImprintBodyTool: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.ImprintBodyTool", fields: 2)
        try encoder.field("body", body)
        try encoder.field("placement", placement)
    }
}
