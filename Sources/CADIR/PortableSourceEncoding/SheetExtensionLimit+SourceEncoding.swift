import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SheetExtensionLimit`.
extension CADIR.SheetExtensionLimit: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.SheetExtensionLimit", fields: 3)
        try encoder.field("body", body)
        try encoder.field("mode", mode)
        try encoder.field("placement", placement)
    }
}
