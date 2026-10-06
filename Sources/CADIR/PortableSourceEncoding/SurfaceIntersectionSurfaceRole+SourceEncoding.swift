import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.SurfaceIntersectionSurfaceRole`.
extension CADGeometry.SurfaceIntersectionSurfaceRole: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.enumeration("CADGeometry.SurfaceIntersectionSurfaceRole", caseName: rawValue, values: 0)
    }
}
