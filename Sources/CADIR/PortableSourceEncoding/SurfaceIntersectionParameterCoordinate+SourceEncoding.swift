import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.SurfaceIntersectionParameterCoordinate`.
extension CADGeometry.SurfaceIntersectionParameterCoordinate: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.enumeration("CADGeometry.SurfaceIntersectionParameterCoordinate", caseName: "raw", values: 1, using: &admission)
        try encoder.field("rawValue", rawValue, using: &admission)
    }
}
