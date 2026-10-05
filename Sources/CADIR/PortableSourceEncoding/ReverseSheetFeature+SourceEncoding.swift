import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.ReverseSheetFeature`.
extension CADIR.ReverseSheetFeature: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.ReverseSheetFeature", fields: 1)
        try encoder.field("target", target)
    }
}
