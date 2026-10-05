import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.ProductSavedView.Projection`.
extension CADIR.ProductSavedView.Projection: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.enumeration("CADIR.ProductSavedView.Projection", caseName: rawValue, values: 0)
    }
}
