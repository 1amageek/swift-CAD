import CADCore
import CADGeometry

/// Encodes the complete original plane derivative source, excluding derived caches.
extension CADGeometry.OriginalPlaneDerivativeConstraint: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADGeometry.OriginalPlaneDerivativeConstraint", fields: 2, using: &admission)
        try encoder.field("order", order, using: &admission)
        try encoder.field("surface", surface, using: &admission)
    }
}
