import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.OriginalImageSurfaceParameterCurve`.
extension CADGeometry.OriginalImageSurfaceParameterCurve: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADGeometry.OriginalImageSurfaceParameterCurve", fields: 4)
        try encoder.field("endFraction", endFraction)
        try encoder.field("source", source)
        try encoder.field("startFraction", startFraction)
        try encoder.field("targetImage", targetImage)
    }
}
