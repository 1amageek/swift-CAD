import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.OriginalRevolutionSurface3D`.
extension CADGeometry.OriginalRevolutionSurface3D: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADGeometry.OriginalRevolutionSurface3D", fields: 4, using: &admission)
        try encoder.field("axisDirection", axisDirection, using: &admission)
        try encoder.field("axisOrigin", axisOrigin, using: &admission)
        try encoder.field("generator", generator, using: &admission)
        try encoder.field("uDomain", uDomain, using: &admission)
    }
}
