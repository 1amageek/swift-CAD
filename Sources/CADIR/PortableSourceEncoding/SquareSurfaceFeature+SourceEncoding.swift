import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SquareSurfaceFeature`.
extension CADIR.SquareSurfaceFeature: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.SquareSurfaceFeature", fields: 2, using: &admission)
        try encoder.field("options", options, using: &admission)
        try encoder.field("sides", sides, using: &admission)
    }
}
