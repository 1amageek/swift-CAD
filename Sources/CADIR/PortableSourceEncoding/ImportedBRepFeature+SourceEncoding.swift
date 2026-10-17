import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.ImportedBRepFeature`.
extension CADIR.ImportedBRepFeature: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.ImportedBRepFeature", fields: 2, using: &admission)
        try encoder.field("model", model, using: &admission)
        try encoder.field("sourceUnits", sourceUnits, using: &admission)
    }
}
