import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.ProductAnnotationTextLiteral.Path`.
extension CADIR.ProductAnnotationTextLiteral.Path: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.enumeration("CADIR.ProductAnnotationTextLiteral.Path", caseName: rawValue, values: 0)
    }
}
