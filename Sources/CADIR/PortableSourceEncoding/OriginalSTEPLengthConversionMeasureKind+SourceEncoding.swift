import CADCore

/// Retains the original length measure family.
extension OriginalSTEPLengthConversion.MeasureKind: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try rawValue.encodeSource(to: &encoder, using: &admission)
    }
}
