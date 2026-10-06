import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.FeaturePort`.
extension CADIR.FeaturePort: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.enumeration("CADIR.FeaturePort", caseName: rawValue, values: 0)
    }
}
