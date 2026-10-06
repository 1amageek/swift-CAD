import CADCore

/// Encodes the original group ordering and inverse-membership family.
extension CADIR.IndependentShapeGroupFamily: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.IndependentShapeGroupFamily", fields: 1)
        try encoder.field("rawValue", rawValue)
    }
}
