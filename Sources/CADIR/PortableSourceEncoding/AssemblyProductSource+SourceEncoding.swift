import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.AssemblyProductSource`.
extension CADIR.AssemblyProductSource: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.enumeration("CADIR.AssemblyProductSource", caseName: rawValue, values: 0)
    }
}
