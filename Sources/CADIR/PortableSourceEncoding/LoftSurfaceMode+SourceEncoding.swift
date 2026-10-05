import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.LoftSurfaceMode`.
extension CADIR.LoftSurfaceMode: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.enumeration("CADIR.LoftSurfaceMode", caseName: rawValue, values: 0)
    }
}
