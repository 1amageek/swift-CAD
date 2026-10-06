import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SurfaceEdgeContinuity.Order`.
extension CADIR.SurfaceEdgeContinuity.Order: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.enumeration("CADIR.SurfaceEdgeContinuity.Order", caseName: rawValue, values: 0)
    }
}
