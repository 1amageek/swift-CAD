import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADTopology.BodyKind`.
extension CADTopology.BodyKind: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.enumeration("CADTopology.BodyKind", caseName: rawValue, values: 0, using: &admission)
    }
}
