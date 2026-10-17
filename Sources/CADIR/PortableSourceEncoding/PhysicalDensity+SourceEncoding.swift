import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.PhysicalDensity`.
extension CADIR.PhysicalDensity: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.PhysicalDensity", fields: 1, using: &admission)
        try encoder.field("kilogramsPerCubicMeter", kilogramsPerCubicMeter, using: &admission)
    }
}
