import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.AffineTransform3D`.
extension CADGeometry.AffineTransform3D: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADGeometry.AffineTransform3D", fields: 4)
        try encoder.field("basisX", basisX)
        try encoder.field("basisY", basisY)
        try encoder.field("basisZ", basisZ)
        try encoder.field("translation", translation)
    }
}
