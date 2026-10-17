import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.IndependentShapeAngularConversion.MeasureKind`.
extension CADIR.IndependentShapeAngularConversion.MeasureKind: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.enumeration("CADIR.IndependentShapeAngularConversion.MeasureKind", caseName: rawValue, values: 0, using: &admission)
    }
}
