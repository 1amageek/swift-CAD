import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.EdgeParameterReference`.
extension CADIR.EdgeParameterReference: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.EdgeParameterReference", fields: 2, using: &admission)
        try encoder.field("edge", edge, using: &admission)
        try encoder.field("parameter", parameter, using: &admission)
    }
}
