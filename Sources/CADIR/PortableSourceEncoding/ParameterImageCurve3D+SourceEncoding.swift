import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.ParameterImageCurve3D`.
extension CADGeometry.ParameterImageCurve3D: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADGeometry.ParameterImageCurve3D", fields: 3, using: &admission)
        try encoder.field("offset", offset, using: &admission)
        try encoder.field("parameterGain", parameterGain, using: &admission)
        try encoder.field("source", source, using: &admission)
    }
}
