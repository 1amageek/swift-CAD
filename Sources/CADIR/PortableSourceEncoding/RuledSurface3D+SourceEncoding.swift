import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.RuledSurface3D`.
extension CADGeometry.RuledSurface3D: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADGeometry.RuledSurface3D", fields: 3, using: &admission)
        try encoder.field("endBoundary", endBoundary, using: &admission)
        try encoder.field("startBoundary", startBoundary, using: &admission)
        try encoder.field("uDomain", uDomain, using: &admission)
    }
}
