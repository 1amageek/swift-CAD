import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.ProductClippingPlane`.
extension CADIR.ProductClippingPlane: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.ProductClippingPlane", fields: 3)
        try encoder.field("keepPositive", keepPositive)
        try encoder.field("normal", normal)
        try encoder.field("origin", origin)
    }
}
