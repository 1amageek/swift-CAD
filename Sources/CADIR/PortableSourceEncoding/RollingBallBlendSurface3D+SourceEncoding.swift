import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.RollingBallBlendSurface3D`.
extension CADGeometry.RollingBallBlendSurface3D: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADGeometry.RollingBallBlendSurface3D", fields: 5, using: &admission)
        try encoder.field("centerSpine", centerSpine, using: &admission)
        try encoder.field("firstContact", firstContact, using: &admission)
        try encoder.field("radius", radius, using: &admission)
        try encoder.field("secondContact", secondContact, using: &admission)
        try encoder.field("tolerance", tolerance, using: &admission)
    }
}
