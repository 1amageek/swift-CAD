import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SurfaceContinuityLevel`.
extension CADIR.SurfaceContinuityLevel: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.enumeration("CADIR.SurfaceContinuityLevel", caseName: "raw", values: 1, using: &admission)
        try encoder.field("rawValue", rawValue, using: &admission)
    }
}
