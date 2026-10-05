import CADCore
import CADGeometry

/// Retains the original requested derivative order.
extension CADGeometry.OriginalPlaneDerivativeOrder: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.enumeration("CADGeometry.OriginalPlaneDerivativeOrder", caseName: String(rawValue), values: 0)
    }
}
