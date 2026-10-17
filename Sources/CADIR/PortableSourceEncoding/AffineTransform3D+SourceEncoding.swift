import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.AffineTransform3D`.
extension CADGeometry.AffineTransform3D: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADGeometry.AffineTransform3D", fields: 4, using: &admission)
        try encoder.field("basisX", basisX, using: &admission)
        try encoder.field("basisY", basisY, using: &admission)
        try encoder.field("basisZ", basisZ, using: &admission)
        try encoder.field("translation", translation, using: &admission)
    }
}
