import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.ProductAnnotationTextLiteral.Path`.
extension CADIR.ProductAnnotationTextLiteral.Path: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.enumeration("CADIR.ProductAnnotationTextLiteral.Path", caseName: rawValue, values: 0, using: &admission)
    }
}
