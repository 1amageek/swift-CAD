import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.DirectScale`.
extension CADIR.DirectScale: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.DirectScale", fields: 4)
        try encoder.field("factors", factors)
        try encoder.field("origin", origin)
        try encoder.field("xAxis", xAxis)
        try encoder.field("yAxis", yAxis)
    }
}
