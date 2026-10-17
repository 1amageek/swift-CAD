import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.ImprintBodyFeature`.
extension CADIR.ImprintBodyFeature: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.ImprintBodyFeature", fields: 3, using: &admission)
        try encoder.field("completion", completion, using: &admission)
        try encoder.field("target", target, using: &admission)
        try encoder.field("tools", tools, using: &admission)
    }
}
