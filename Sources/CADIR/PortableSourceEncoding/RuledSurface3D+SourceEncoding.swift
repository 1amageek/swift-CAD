import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.RuledSurface3D`.
extension CADGeometry.RuledSurface3D: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADGeometry.RuledSurface3D", fields: 3)
        try encoder.field("endBoundary", endBoundary)
        try encoder.field("startBoundary", startBoundary)
        try encoder.field("uDomain", uDomain)
    }
}
