import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SurfaceContinuityLevel`.
extension CADIR.SurfaceContinuityLevel: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.enumeration("CADIR.SurfaceContinuityLevel", caseName: "raw", values: 1)
        try encoder.field("rawValue", rawValue)
    }
}
