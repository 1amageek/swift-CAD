import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.LoftSectionMatching`.
extension CADIR.LoftSectionMatching: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.enumeration("CADIR.LoftSectionMatching", caseName: rawValue, values: 0)
    }
}
