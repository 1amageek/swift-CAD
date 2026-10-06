import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.ParameterImageCurve3D`.
extension CADGeometry.ParameterImageCurve3D: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADGeometry.ParameterImageCurve3D", fields: 3)
        try encoder.field("offset", offset)
        try encoder.field("parameterGain", parameterGain)
        try encoder.field("source", source)
    }
}
