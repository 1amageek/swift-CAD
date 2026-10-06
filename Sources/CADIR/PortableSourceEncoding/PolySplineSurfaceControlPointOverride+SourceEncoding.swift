import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.PolySplineSurfaceControlPointOverride`.
extension CADIR.PolySplineSurfaceControlPointOverride: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.PolySplineSurfaceControlPointOverride", fields: 5)
        try encoder.field("patchID", patchID)
        try encoder.field("point", point)
        try encoder.field("uIndex", uIndex)
        try encoder.field("vIndex", vIndex)
        try encoder.field("weight", weight)
    }
}
