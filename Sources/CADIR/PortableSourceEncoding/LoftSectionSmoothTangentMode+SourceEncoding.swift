import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.LoftSectionSmoothTangentMode`.
extension CADIR.LoftSectionSmoothTangentMode: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.enumeration("CADIR.LoftSectionSmoothTangentMode", caseName: rawValue, values: 0)
    }
}
