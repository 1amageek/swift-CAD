import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.ProductShapeElementDescription`.
extension CADIR.ProductShapeElementDescription: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.ProductShapeElementDescription", fields: 2, using: &admission)
        try encoder.field("description", description, using: &admission)
        try encoder.field("target", target, using: &admission)
    }
}
