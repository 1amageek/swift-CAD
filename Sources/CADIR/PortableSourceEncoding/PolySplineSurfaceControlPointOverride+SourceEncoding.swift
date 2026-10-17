import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.PolySplineSurfaceControlPointOverride`.
extension CADIR.PolySplineSurfaceControlPointOverride: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.PolySplineSurfaceControlPointOverride", fields: 5, using: &admission)
        try encoder.field("patchID", patchID, using: &admission)
        try encoder.field("point", point, using: &admission)
        try encoder.field("uIndex", uIndex, using: &admission)
        try encoder.field("vIndex", vIndex, using: &admission)
        try encoder.field("weight", weight, using: &admission)
    }
}
