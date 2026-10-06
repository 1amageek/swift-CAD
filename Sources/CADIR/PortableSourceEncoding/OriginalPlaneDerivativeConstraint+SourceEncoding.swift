import CADCore
import CADGeometry

/// Encodes the complete original plane derivative source, excluding derived caches.
extension CADGeometry.OriginalPlaneDerivativeConstraint: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADGeometry.OriginalPlaneDerivativeConstraint", fields: 2)
        try encoder.field("order", order)
        try encoder.field("surface", surface)
    }
}
