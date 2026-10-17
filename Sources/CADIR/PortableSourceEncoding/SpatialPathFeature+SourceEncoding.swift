import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SpatialPathFeature`.
extension CADIR.SpatialPathFeature: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.SpatialPathFeature", fields: 3, using: &admission)
        try encoder.field("isClosed", isClosed, using: &admission)
        try encoder.field("kind", kind, using: &admission)
        try encoder.field("knots", knots, using: &admission)
    }
}
