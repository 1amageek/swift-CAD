import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.MirrorFeature.Output`.
extension CADIR.MirrorFeature.Output: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.enumeration("CADIR.MirrorFeature.Output", caseName: rawValue, values: 0, using: &admission)
    }
}
