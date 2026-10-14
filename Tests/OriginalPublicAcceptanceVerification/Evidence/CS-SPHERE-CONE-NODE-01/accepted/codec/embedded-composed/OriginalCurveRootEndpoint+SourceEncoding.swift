import CADCore

/// Encodes original source fields owned by `CADGeometry.OriginalCurveRootEndpoint`.
extension CADGeometry.OriginalCurveRootEndpoint: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        switch self {
        case let .authored(value0):
            try encoder.enumeration("CADGeometry.OriginalCurveRootEndpoint", caseName: "authored", values: 1)
            try encoder.field("_0", value0)
        case let .algebraic(value0):
            try encoder.enumeration("CADGeometry.OriginalCurveRootEndpoint", caseName: "algebraic", values: 1)
            try encoder.field("_0", value0)
        }
    }
}
