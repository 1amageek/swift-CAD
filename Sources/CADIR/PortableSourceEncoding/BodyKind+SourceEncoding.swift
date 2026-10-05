import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADTopology.BodyKind`.
extension CADTopology.BodyKind: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.enumeration("CADTopology.BodyKind", caseName: rawValue, values: 0)
    }
}
