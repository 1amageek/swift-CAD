import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.BSplineSurfaceFeature`.
extension CADIR.BSplineSurfaceFeature: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.BSplineSurfaceFeature", fields: 3, using: &admission)
        try encoder.field("material", material, using: &admission)
        try encoder.field("parameterDomain", parameterDomain, using: &admission)
        try encoder.field("surface", surface, using: &admission)
    }
}
