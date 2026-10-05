import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.MirrorFeature.Output`.
extension CADIR.MirrorFeature.Output: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.enumeration("CADIR.MirrorFeature.Output", caseName: rawValue, values: 0)
    }
}
