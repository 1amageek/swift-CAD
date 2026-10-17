import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.RigidImageSurfaceParameterCurve`.
extension CADGeometry.RigidImageSurfaceParameterCurve: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADGeometry.RigidImageSurfaceParameterCurve", fields: 5, using: &admission)
        try encoder.field("endFraction", endFraction, using: &admission)
        try encoder.field("source", source, using: &admission)
        try encoder.field("startFraction", startFraction, using: &admission)
        try encoder.field("targetSurface", targetSurface, using: &admission)
        try encoder.field("transform", transform, using: &admission)
    }
}
