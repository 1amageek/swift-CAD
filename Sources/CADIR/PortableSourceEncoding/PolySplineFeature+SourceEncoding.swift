import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.PolySplineFeature`.
extension CADIR.PolySplineFeature: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.PolySplineFeature", fields: 3)
        try encoder.field("controlPointOverrides", controlPointOverrides)
        try encoder.field("options", options)
        try encoder.field("sourceMesh", sourceMesh)
    }
}
