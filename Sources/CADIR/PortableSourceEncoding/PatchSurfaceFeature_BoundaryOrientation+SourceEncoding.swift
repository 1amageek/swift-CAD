import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.PatchSurfaceFeature.BoundaryOrientation`.
extension CADIR.PatchSurfaceFeature.BoundaryOrientation: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.enumeration("CADIR.PatchSurfaceFeature.BoundaryOrientation", caseName: rawValue, values: 0)
    }
}
