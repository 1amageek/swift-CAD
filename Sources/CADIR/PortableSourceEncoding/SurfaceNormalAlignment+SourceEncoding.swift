import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SurfaceNormalAlignment`.
extension CADIR.SurfaceNormalAlignment: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.enumeration("CADIR.SurfaceNormalAlignment", caseName: rawValue, values: 0)
    }
}
