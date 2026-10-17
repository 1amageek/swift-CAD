import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.OriginalImageSurface3D`.
extension CADGeometry.OriginalImageSurface3D: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADGeometry.OriginalImageSurface3D", fields: 7, using: &admission)
        try encoder.field("source", source, using: &admission)
        try encoder.field("swapAxes", swapAxes, using: &admission)
        try encoder.field("transform", transform, using: &admission)
        try encoder.field("uOffset", uOffset, using: &admission)
        try encoder.field("uParameterGain", uParameterGain, using: &admission)
        try encoder.field("vOffset", vOffset, using: &admission)
        try encoder.field("vParameterGain", vParameterGain, using: &admission)
    }
}
