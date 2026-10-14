import CADCore

/// Retains the original normalized placement family.
extension OriginalNormalizedAffineSource.Family: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try rawValue.encodeSource(to: &encoder)
    }
}
