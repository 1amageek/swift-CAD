import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.PolySplineFeature`.
extension CADIR.PolySplineFeature: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.PolySplineFeature", fields: 3, using: &admission)
        try encoder.field("controlPointOverrides", controlPointOverrides, using: &admission)
        try encoder.field("options", options, using: &admission)
        try encoder.field("sourceMesh", sourceMesh, using: &admission)
    }
}
