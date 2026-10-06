import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.CurveEditFeature`.
extension CADIR.CurveEditFeature: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.CurveEditFeature", fields: 2)
        try encoder.field("edits", edits)
        try encoder.field("source", source)
    }
}
