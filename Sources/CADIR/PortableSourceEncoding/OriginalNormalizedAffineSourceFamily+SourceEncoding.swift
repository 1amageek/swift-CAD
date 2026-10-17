import CADCore
import CADGeometry

/// Retains the original normalized placement family.
extension OriginalNormalizedAffineSource.Family: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try rawValue.encodeSource(to: &encoder, using: &admission)
    }
}
