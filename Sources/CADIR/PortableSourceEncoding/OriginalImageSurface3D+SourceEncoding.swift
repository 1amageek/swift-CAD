import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.OriginalImageSurface3D`.
extension CADGeometry.OriginalImageSurface3D: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADGeometry.OriginalImageSurface3D", fields: 7)
        try encoder.field("source", source)
        try encoder.field("swapAxes", swapAxes)
        try encoder.field("transform", transform)
        try encoder.field("uOffset", uOffset)
        try encoder.field("uParameterGain", uParameterGain)
        try encoder.field("vOffset", vOffset)
        try encoder.field("vParameterGain", vParameterGain)
    }
}
