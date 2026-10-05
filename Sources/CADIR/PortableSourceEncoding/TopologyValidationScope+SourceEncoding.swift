import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADTopology.TopologyValidationScope`.
extension CADTopology.TopologyValidationScope: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.enumeration("CADTopology.TopologyValidationScope", caseName: rawValue, values: 0)
    }
}
