import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.OriginalImageSurfaceParameterCurve`.
extension CADGeometry.OriginalImageSurfaceParameterCurve: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADGeometry.OriginalImageSurfaceParameterCurve", fields: 4, using: &admission)
        try encoder.field("endFraction", endFraction, using: &admission)
        try encoder.field("source", source, using: &admission)
        try encoder.field("startFraction", startFraction, using: &admission)
        try encoder.field("targetImage", targetImage, using: &admission)
    }
}
