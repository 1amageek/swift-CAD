import CADCore
import CADGeometry

/// Retains the original connector's authored correction basis.
extension CADGeometry.OriginalEndpointCorrectionBasis: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.enumeration("CADGeometry.OriginalEndpointCorrectionBasis", caseName: rawValue, values: 0, using: &admission)
    }
}
