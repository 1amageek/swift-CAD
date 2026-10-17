import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADTopology.LoopRole`.
extension CADTopology.LoopRole: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.enumeration("CADTopology.LoopRole", caseName: rawValue, values: 0, using: &admission)
    }
}
