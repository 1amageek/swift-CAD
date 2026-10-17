import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SheetExtensionLimit`.
extension CADIR.SheetExtensionLimit: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.SheetExtensionLimit", fields: 3, using: &admission)
        try encoder.field("body", body, using: &admission)
        try encoder.field("mode", mode, using: &admission)
        try encoder.field("placement", placement, using: &admission)
    }
}
