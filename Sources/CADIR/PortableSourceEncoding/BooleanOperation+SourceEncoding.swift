import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.BooleanOperation`.
extension CADIR.BooleanOperation: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.enumeration("CADIR.BooleanOperation", caseName: rawValue, values: 0)
    }
}
