import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SolidOperation`.
extension CADIR.SolidOperation: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.enumeration("CADIR.SolidOperation", caseName: rawValue, values: 0)
    }
}
