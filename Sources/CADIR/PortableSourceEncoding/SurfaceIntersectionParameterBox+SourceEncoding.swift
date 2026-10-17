import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.SurfaceIntersectionParameterBox`.
extension CADGeometry.SurfaceIntersectionParameterBox: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADGeometry.SurfaceIntersectionParameterBox", fields: 4, using: &admission)
        try encoder.field("firstU", firstU, using: &admission)
        try encoder.field("firstV", firstV, using: &admission)
        try encoder.field("secondU", secondU, using: &admission)
        try encoder.field("secondV", secondV, using: &admission)
    }
}
