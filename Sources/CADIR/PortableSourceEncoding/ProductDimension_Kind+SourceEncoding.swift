import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.ProductDimension.Kind`.
extension CADIR.ProductDimension.Kind: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.enumeration("CADIR.ProductDimension.Kind", caseName: rawValue, values: 0)
    }
}
