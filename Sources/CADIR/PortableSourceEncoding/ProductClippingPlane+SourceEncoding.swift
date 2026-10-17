import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.ProductClippingPlane`.
extension CADIR.ProductClippingPlane: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.ProductClippingPlane", fields: 3, using: &admission)
        try encoder.field("keepPositive", keepPositive, using: &admission)
        try encoder.field("normal", normal, using: &admission)
        try encoder.field("origin", origin, using: &admission)
    }
}
