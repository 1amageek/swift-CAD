import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.RevolveAxis`.
extension CADIR.RevolveAxis: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.RevolveAxis", fields: 2)
        try encoder.field("direction", direction)
        try encoder.field("origin", origin)
    }
}
