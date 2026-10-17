import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.ProductAttributeTarget.Kind`.
extension CADIR.ProductAttributeTarget.Kind: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.enumeration("CADIR.ProductAttributeTarget.Kind", caseName: rawValue, values: 0, using: &admission)
    }
}
