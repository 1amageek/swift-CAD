import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.ImportedBRepFeature`.
extension CADIR.ImportedBRepFeature: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.ImportedBRepFeature", fields: 2)
        try encoder.field("model", model)
        try encoder.field("sourceUnits", sourceUnits)
    }
}
