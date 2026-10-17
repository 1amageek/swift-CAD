import CADCore

/// Encodes the original group ordering and inverse-membership family.
extension CADIR.IndependentShapeGroupFamily: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.IndependentShapeGroupFamily", fields: 1, using: &admission)
        try encoder.field("rawValue", rawValue, using: &admission)
    }
}
