import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.AffineImageCurve3D`.
extension CADGeometry.AffineImageCurve3D: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADGeometry.AffineImageCurve3D", fields: 2, using: &admission)
        try encoder.field("source", source, using: &admission)
        try encoder.field("transform", transform, using: &admission)
    }
}
