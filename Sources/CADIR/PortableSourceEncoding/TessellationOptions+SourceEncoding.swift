import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.TessellationOptions`.
extension CADIR.TessellationOptions: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.TessellationOptions", fields: 5, using: &admission)
        try encoder.field("angularTolerance", angularTolerance, using: &admission)
        try encoder.field("faceOverrides", faceOverrides, using: &admission)
        try encoder.field("featureOverrides", featureOverrides, using: &admission)
        try encoder.field("linearTolerance", linearTolerance, using: &admission)
        try encoder.field("maxEdgeLength", maxEdgeLength, using: &admission)
    }
}
