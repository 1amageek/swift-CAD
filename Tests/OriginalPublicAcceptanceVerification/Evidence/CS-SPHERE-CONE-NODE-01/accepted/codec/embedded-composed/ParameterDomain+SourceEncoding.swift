import CADCore

/// Encodes original source fields owned by `CADGeometry.ParameterDomain`.
extension CADGeometry.ParameterDomain: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        switch self {
        case .unbounded:
            try encoder.enumeration("CADGeometry.ParameterDomain", caseName: "unbounded", values: 0)
        case let .closed(value0, value1):
            try encoder.enumeration("CADGeometry.ParameterDomain", caseName: "closed", values: 2)
            try encoder.field("_0", value0)
            try encoder.field("_1", value1)
        case let .periodic(value0):
            try encoder.enumeration("CADGeometry.ParameterDomain", caseName: "periodic", values: 1)
            try encoder.field("_0", value0)
        }
    }
}
