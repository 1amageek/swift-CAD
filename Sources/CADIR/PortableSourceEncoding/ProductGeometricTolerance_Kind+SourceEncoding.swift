import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.ProductGeometricTolerance.Kind`.
extension CADIR.ProductGeometricTolerance.Kind: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.enumeration("CADIR.ProductGeometricTolerance.Kind", caseName: rawValue, values: 0)
    }
}
