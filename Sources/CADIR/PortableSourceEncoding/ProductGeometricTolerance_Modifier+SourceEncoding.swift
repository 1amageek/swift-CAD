import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.ProductGeometricTolerance.Modifier`.
extension CADIR.ProductGeometricTolerance.Modifier: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.enumeration("CADIR.ProductGeometricTolerance.Modifier", caseName: rawValue, values: 0, using: &admission)
    }
}
