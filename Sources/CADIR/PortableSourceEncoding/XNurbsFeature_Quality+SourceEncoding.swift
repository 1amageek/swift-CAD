import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.XNurbsFeature.Quality`.
extension CADIR.XNurbsFeature.Quality: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.enumeration("CADIR.XNurbsFeature.Quality", caseName: rawValue, values: 0)
    }
}
