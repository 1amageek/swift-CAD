import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.OriginalCurveRootSpan3D`.
extension CADGeometry.OriginalCurveRootSpan3D: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADGeometry.OriginalCurveRootSpan3D", fields: 5)
        try encoder.field("certificationTolerance", certificationTolerance)
        try encoder.field("end", end)
        try encoder.field("nativeSpanIndex", nativeSpanIndex)
        try encoder.field("source", source)
        try encoder.field("start", start)
    }
}
