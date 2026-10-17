import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.OffsetSurface3D`.
extension CADGeometry.OffsetSurface3D: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADGeometry.OffsetSurface3D", fields: 2, using: &admission)
        try encoder.field("distance", distance, using: &admission)
        try encoder.field("source", source, using: &admission)
    }
}
