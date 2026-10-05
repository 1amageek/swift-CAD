import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.FilletVariablePoint`.
extension CADIR.FilletVariablePoint: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.FilletVariablePoint", fields: 2)
        try encoder.field("position", position)
        try encoder.field("radius", radius)
    }
}
