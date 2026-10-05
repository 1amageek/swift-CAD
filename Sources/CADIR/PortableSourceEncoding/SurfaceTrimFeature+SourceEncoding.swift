import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SurfaceTrimFeature`.
extension CADIR.SurfaceTrimFeature: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.SurfaceTrimFeature", fields: 2)
        try encoder.field("loops", loops)
        try encoder.field("target", target)
    }
}
