import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.FilletVariablePoint`.
extension CADIR.FilletVariablePoint: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.FilletVariablePoint", fields: 2, using: &admission)
        try encoder.field("position", position, using: &admission)
        try encoder.field("radius", radius, using: &admission)
    }
}
