import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.TessellationOptions`.
extension CADIR.TessellationOptions: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.TessellationOptions", fields: 5)
        try encoder.field("angularTolerance", angularTolerance)
        try encoder.field("faceOverrides", faceOverrides)
        try encoder.field("featureOverrides", featureOverrides)
        try encoder.field("linearTolerance", linearTolerance)
        try encoder.field("maxEdgeLength", maxEdgeLength)
    }
}
