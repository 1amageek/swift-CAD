import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.ProductAnnotationTextLiteral.Placement`.
extension CADIR.ProductAnnotationTextLiteral.Placement: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.enumeration("CADIR.ProductAnnotationTextLiteral.Placement", caseName: rawValue, values: 0)
    }
}
