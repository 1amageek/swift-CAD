import CADCore
import CADGeometry

/// Retains the original requested derivative order.
extension CADGeometry.OriginalPlaneDerivativeOrder: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.enumeration("CADGeometry.OriginalPlaneDerivativeOrder", caseName: String(rawValue), values: 0, using: &admission)
    }
}
