import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADTopology.LoopRole`.
extension CADTopology.LoopRole: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.enumeration("CADTopology.LoopRole", caseName: rawValue, values: 0)
    }
}
