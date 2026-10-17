import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.ProductSavedView.WindowPlacement`.
extension CADIR.ProductSavedView.WindowPlacement: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.enumeration("CADIR.ProductSavedView.WindowPlacement", caseName: rawValue, values: 0, using: &admission)
    }
}
