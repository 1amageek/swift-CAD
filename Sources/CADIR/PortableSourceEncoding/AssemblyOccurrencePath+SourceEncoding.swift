import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.AssemblyOccurrencePath`.
extension CADIR.AssemblyOccurrencePath: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.AssemblyOccurrencePath", fields: 1, using: &admission)
        try encoder.field("components", components, using: &admission)
    }
}
