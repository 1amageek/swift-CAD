import CADCore
import CADGeometry

extension OriginalCurveConstructionParameterLaw: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.enumeration("CADGeometry.OriginalCurveConstructionParameterLaw", caseName: rawValue, values: 0, using: &admission)
    }
}
