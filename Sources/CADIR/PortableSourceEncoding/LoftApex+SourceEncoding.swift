import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.LoftApex`.
extension CADIR.LoftApex: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.LoftApex", fields: 3)
        try encoder.field("bodyRole", bodyRole)
        try encoder.field("source", source)
        try encoder.field("vertex", vertex)
    }
}
