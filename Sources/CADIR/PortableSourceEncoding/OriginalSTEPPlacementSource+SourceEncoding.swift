import CADCore

/// Encodes the actual original STEP placement family and complete raw payload.
extension OriginalSTEPPlacementSource: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        switch self {
        case .axis2(let value):
            try encoder.enumeration("CADIR.OriginalSTEPPlacementSource", caseName: "axis2", values: 1)
            try encoder.field("_0", value)
        case .cartesian(let value):
            try encoder.enumeration("CADIR.OriginalSTEPPlacementSource", caseName: "cartesian", values: 1)
            try encoder.field("_0", value)
        }
    }
}
