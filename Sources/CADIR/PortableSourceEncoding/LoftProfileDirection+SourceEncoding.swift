import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.LoftProfileDirection`.
extension CADIR.LoftProfileDirection: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.enumeration("CADIR.LoftProfileDirection", caseName: rawValue, values: 0)
    }
}
