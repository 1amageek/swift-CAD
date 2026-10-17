/// Encodes original source fields owned by `CADCore.BezierExtensionShape`.
extension CADCore.BezierExtensionShape: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        switch self {
        case let .arc(value0):
            try encoder.enumeration("CADCore.BezierExtensionShape", caseName: "arc", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .soft(value0):
            try encoder.enumeration("CADCore.BezierExtensionShape", caseName: "soft", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .reflective(value0, value1):
            try encoder.enumeration("CADCore.BezierExtensionShape", caseName: "reflective", values: 2, using: &admission)
            try encoder.field("_0", value0, using: &admission)
            try encoder.field("_1", value1, using: &admission)
        }
    }
}
