import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.ProductAnnotation.Meaning`.
extension CADIR.ProductAnnotation.Meaning: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.enumeration("CADIR.ProductAnnotation.Meaning", caseName: rawValue, values: 0)
    }
}
