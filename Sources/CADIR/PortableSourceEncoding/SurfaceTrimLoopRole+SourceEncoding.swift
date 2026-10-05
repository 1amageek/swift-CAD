import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SurfaceTrimLoopRole`.
extension CADIR.SurfaceTrimLoopRole: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.enumeration("CADIR.SurfaceTrimLoopRole", caseName: rawValue, values: 0)
    }
}
