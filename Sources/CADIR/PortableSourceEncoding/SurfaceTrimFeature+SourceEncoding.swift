import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SurfaceTrimFeature`.
extension CADIR.SurfaceTrimFeature: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.SurfaceTrimFeature", fields: 2, using: &admission)
        try encoder.field("loops", loops, using: &admission)
        try encoder.field("target", target, using: &admission)
    }
}
