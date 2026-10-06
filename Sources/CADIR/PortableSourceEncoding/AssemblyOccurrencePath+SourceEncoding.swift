import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.AssemblyOccurrencePath`.
extension CADIR.AssemblyOccurrencePath: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.AssemblyOccurrencePath", fields: 1)
        try encoder.field("components", components)
    }
}
