import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.IndependentShapeAngularConversion.Interpretation`.
extension CADIR.IndependentShapeAngularConversion.Interpretation: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.enumeration("CADIR.IndependentShapeAngularConversion.Interpretation", caseName: rawValue, values: 0, using: &admission)
    }
}
