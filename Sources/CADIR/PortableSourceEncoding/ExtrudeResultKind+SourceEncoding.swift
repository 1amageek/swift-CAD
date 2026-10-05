import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.ExtrudeResultKind`.
extension CADIR.ExtrudeResultKind: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.enumeration("CADIR.ExtrudeResultKind", caseName: rawValue, values: 0)
    }
}
