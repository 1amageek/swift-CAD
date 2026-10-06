import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.ParameterTable`.
extension CADIR.ParameterTable: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.ParameterTable", fields: 1)
        try encoder.field("parameters", parameters)
    }
}
