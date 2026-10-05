import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.IndependentShapeAngularConversion`.
extension CADIR.IndependentShapeAngularConversion: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.IndependentShapeAngularConversion", fields: 8)
        try encoder.field("base", base)
        try encoder.field("dimensions", dimensions)
        try encoder.field("dimensionsID", dimensionsID)
        try encoder.field("factor", factor)
        try encoder.field("interpretation", interpretation)
        try encoder.field("measureID", measureID)
        try encoder.field("measureKind", measureKind)
        try encoder.field("name", name)
    }
}
