import CADCore

/// Encodes the actual original STEP placement family and complete raw payload.
extension OriginalSTEPPlacementSource: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        switch self {
        case .axis2(let value):
            try encoder.enumeration("CADIR.OriginalSTEPPlacementSource", caseName: "axis2", values: 1, using: &admission)
            try encoder.field("_0", value, using: &admission)
        case .cartesian(let value):
            try encoder.enumeration("CADIR.OriginalSTEPPlacementSource", caseName: "cartesian", values: 1, using: &admission)
            try encoder.field("_0", value, using: &admission)
        }
    }
}
