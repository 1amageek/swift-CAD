import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.DirectScale`.
extension CADIR.DirectScale: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.DirectScale", fields: 4, using: &admission)
        try encoder.field("factors", factors, using: &admission)
        try encoder.field("origin", origin, using: &admission)
        try encoder.field("xAxis", xAxis, using: &admission)
        try encoder.field("yAxis", yAxis, using: &admission)
    }
}
