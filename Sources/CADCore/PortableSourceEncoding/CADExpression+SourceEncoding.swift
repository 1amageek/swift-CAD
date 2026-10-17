/// Encodes original source fields owned by `CADCore.CADExpression`.
extension CADCore.CADExpression: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        switch self {
        case let .constant(value0):
            try encoder.enumeration("CADCore.CADExpression", caseName: "constant", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .reference(value0):
            try encoder.enumeration("CADCore.CADExpression", caseName: "reference", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .variable(value0, value1):
            try encoder.enumeration("CADCore.CADExpression", caseName: "variable", values: 2, using: &admission)
            try encoder.field("_0", value0, using: &admission)
            try encoder.field("_1", value1, using: &admission)
        case let .add(value0, value1):
            try encoder.enumeration("CADCore.CADExpression", caseName: "add", values: 2, using: &admission)
            try encoder.field("_0", value0, using: &admission)
            try encoder.field("_1", value1, using: &admission)
        case let .subtract(value0, value1):
            try encoder.enumeration("CADCore.CADExpression", caseName: "subtract", values: 2, using: &admission)
            try encoder.field("_0", value0, using: &admission)
            try encoder.field("_1", value1, using: &admission)
        case let .multiply(value0, value1):
            try encoder.enumeration("CADCore.CADExpression", caseName: "multiply", values: 2, using: &admission)
            try encoder.field("_0", value0, using: &admission)
            try encoder.field("_1", value1, using: &admission)
        case let .divide(value0, value1):
            try encoder.enumeration("CADCore.CADExpression", caseName: "divide", values: 2, using: &admission)
            try encoder.field("_0", value0, using: &admission)
            try encoder.field("_1", value1, using: &admission)
        case let .hypot(value0, value1):
            try encoder.enumeration("CADCore.CADExpression", caseName: "hypot", values: 2, using: &admission)
            try encoder.field("_0", value0, using: &admission)
            try encoder.field("_1", value1, using: &admission)
        case let .bezierNaturalExtension(value0, value1, value2):
            try encoder.enumeration("CADCore.CADExpression", caseName: "bezierNaturalExtension", values: 3, using: &admission)
            try encoder.field("_0", value0, using: &admission)
            try encoder.field("_1", value1, using: &admission)
            try encoder.field("_2", value2, using: &admission)
        case let .bezierShapedExtension(value0, value1, value2, value3):
            try encoder.enumeration("CADCore.CADExpression", caseName: "bezierShapedExtension", values: 4, using: &admission)
            try encoder.field("_0", value0, using: &admission)
            try encoder.field("_1", value1, using: &admission)
            try encoder.field("_2", value2, using: &admission)
            try encoder.field("_3", value3, using: &admission)
        case let .sin(value0):
            try encoder.enumeration("CADCore.CADExpression", caseName: "sin", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .cos(value0):
            try encoder.enumeration("CADCore.CADExpression", caseName: "cos", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .tan(value0):
            try encoder.enumeration("CADCore.CADExpression", caseName: "tan", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        }
    }
}
