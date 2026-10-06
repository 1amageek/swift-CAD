import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SquareSurfaceFeature`.
extension CADIR.SquareSurfaceFeature: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.SquareSurfaceFeature", fields: 2)
        try encoder.field("options", options)
        try encoder.field("sides", sides)
    }
}
