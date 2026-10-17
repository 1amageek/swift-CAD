import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.ParameterTable`.
extension CADIR.ParameterTable: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.ParameterTable", fields: 1, using: &admission)
        try encoder.field("parameters", parameters, using: &admission)
    }
}
