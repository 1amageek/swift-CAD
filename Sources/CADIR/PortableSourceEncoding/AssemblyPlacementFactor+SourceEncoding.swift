import CADCore

/// Encodes the original direct placement and its authored operation.
extension AssemblyPlacementFactor: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        switch self {
        case .forward(let value):
            try encoder.enumeration("CADIR.AssemblyPlacementFactor", caseName: "forward", values: 1)
            try encoder.field("_0", value)
        case .inverse(let value):
            try encoder.enumeration("CADIR.AssemblyPlacementFactor", caseName: "inverse", values: 1)
            try encoder.field("_0", value)
        }
    }
}
