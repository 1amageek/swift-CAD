import CADCore

/// Encodes the original direct placement and its authored operation.
extension AssemblyPlacementFactor: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        switch self {
        case .forward(let value):
            try encoder.enumeration("CADIR.AssemblyPlacementFactor", caseName: "forward", values: 1, using: &admission)
            try encoder.field("_0", value, using: &admission)
        case .inverse(let value):
            try encoder.enumeration("CADIR.AssemblyPlacementFactor", caseName: "inverse", values: 1, using: &admission)
            try encoder.field("_0", value, using: &admission)
        }
    }
}
