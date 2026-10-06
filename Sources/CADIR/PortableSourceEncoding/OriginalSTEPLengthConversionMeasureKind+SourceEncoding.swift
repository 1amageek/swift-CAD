import CADCore

/// Retains the original length measure family.
extension OriginalSTEPLengthConversion.MeasureKind: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try rawValue.encodeSource(to: &encoder)
    }
}
