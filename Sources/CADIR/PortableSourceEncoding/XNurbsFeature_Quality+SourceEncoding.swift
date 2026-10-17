import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.XNurbsFeature.Quality`.
extension CADIR.XNurbsFeature.Quality: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.enumeration("CADIR.XNurbsFeature.Quality", caseName: rawValue, values: 0, using: &admission)
    }
}
