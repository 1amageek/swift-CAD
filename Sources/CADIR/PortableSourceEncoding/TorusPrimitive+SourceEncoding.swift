import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.TorusPrimitive`.
extension CADIR.TorusPrimitive: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.TorusPrimitive", fields: 3)
        try encoder.field("majorRadius", majorRadius)
        try encoder.field("minorRadius", minorRadius)
        try encoder.field("placement", placement)
    }
}
