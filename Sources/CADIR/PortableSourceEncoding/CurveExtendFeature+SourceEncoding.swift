import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.CurveExtendFeature`.
extension CADIR.CurveExtendFeature: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.CurveExtendFeature", fields: 3, using: &admission)
        try encoder.field("distance", distance, using: &admission)
        try encoder.field("end", end, using: &admission)
        try encoder.field("source", source, using: &admission)
    }
}
