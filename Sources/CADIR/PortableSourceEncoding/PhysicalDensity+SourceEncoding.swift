import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.PhysicalDensity`.
extension CADIR.PhysicalDensity: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.PhysicalDensity", fields: 1)
        try encoder.field("kilogramsPerCubicMeter", kilogramsPerCubicMeter)
    }
}
