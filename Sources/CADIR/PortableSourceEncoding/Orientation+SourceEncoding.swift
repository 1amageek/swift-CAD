import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADTopology.Orientation`.
extension CADTopology.Orientation: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.enumeration("CADTopology.Orientation", caseName: rawValue, values: 0)
    }
}
