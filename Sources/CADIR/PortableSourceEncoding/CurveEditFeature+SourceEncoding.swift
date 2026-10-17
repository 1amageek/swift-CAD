import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.CurveEditFeature`.
extension CADIR.CurveEditFeature: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.CurveEditFeature", fields: 2, using: &admission)
        try encoder.field("edits", edits, using: &admission)
        try encoder.field("source", source, using: &admission)
    }
}
