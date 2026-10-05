import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.ConstrainedSurfaceFeature.Optimization`.
extension CADIR.ConstrainedSurfaceFeature.Optimization: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.enumeration("CADIR.ConstrainedSurfaceFeature.Optimization", caseName: rawValue, values: 0)
    }
}
