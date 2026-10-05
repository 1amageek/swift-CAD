import CADCore
import CADGeometry

/// Retains the original connector's authored correction basis.
extension CADGeometry.OriginalEndpointCorrectionBasis: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.enumeration("CADGeometry.OriginalEndpointCorrectionBasis", caseName: rawValue, values: 0)
    }
}
