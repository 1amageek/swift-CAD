import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.EdgeParameterReference`.
extension CADIR.EdgeParameterReference: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.EdgeParameterReference", fields: 2)
        try encoder.field("edge", edge)
        try encoder.field("parameter", parameter)
    }
}
