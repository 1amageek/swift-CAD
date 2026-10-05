/// Encodes original source fields owned by `CADCore.BezierExtensionShape`.
extension CADCore.BezierExtensionShape: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        switch self {
        case let .arc(value0):
            try encoder.enumeration("CADCore.BezierExtensionShape", caseName: "arc", values: 1)
            try encoder.field("_0", value0)
        case let .soft(value0):
            try encoder.enumeration("CADCore.BezierExtensionShape", caseName: "soft", values: 1)
            try encoder.field("_0", value0)
        case let .reflective(value0, value1):
            try encoder.enumeration("CADCore.BezierExtensionShape", caseName: "reflective", values: 2)
            try encoder.field("_0", value0)
            try encoder.field("_1", value1)
        }
    }
}
