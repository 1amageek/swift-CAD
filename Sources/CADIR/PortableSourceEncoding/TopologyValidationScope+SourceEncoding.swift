import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADTopology.TopologyValidationScope`.
extension CADTopology.TopologyValidationScope: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.enumeration("CADTopology.TopologyValidationScope", caseName: rawValue, values: 0, using: &admission)
    }
}
