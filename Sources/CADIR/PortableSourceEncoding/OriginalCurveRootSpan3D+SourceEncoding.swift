import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.OriginalCurveRootSpan3D`.
extension CADGeometry.OriginalCurveRootSpan3D: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADGeometry.OriginalCurveRootSpan3D", fields: 5, using: &admission)
        try encoder.field("certificationTolerance", certificationTolerance, using: &admission)
        try encoder.field("end", end, using: &admission)
        try encoder.field("nativeSpanIndex", nativeSpanIndex, using: &admission)
        try encoder.field("source", source, using: &admission)
        try encoder.field("start", start, using: &admission)
    }
}
