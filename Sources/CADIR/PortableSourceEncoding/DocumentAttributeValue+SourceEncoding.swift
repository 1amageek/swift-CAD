import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.DocumentAttributeValue`.
extension CADIR.DocumentAttributeValue: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        switch self {
        case let .boolean(value0):
            try encoder.enumeration("CADIR.DocumentAttributeValue", caseName: "boolean", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .integer(value0):
            try encoder.enumeration("CADIR.DocumentAttributeValue", caseName: "integer", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .real(value0):
            try encoder.enumeration("CADIR.DocumentAttributeValue", caseName: "real", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .text(value0):
            try encoder.enumeration("CADIR.DocumentAttributeValue", caseName: "text", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .quantity(value0):
            try encoder.enumeration("CADIR.DocumentAttributeValue", caseName: "quantity", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .integers(value0):
            try encoder.enumeration("CADIR.DocumentAttributeValue", caseName: "integers", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .reals(value0):
            try encoder.enumeration("CADIR.DocumentAttributeValue", caseName: "reals", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .texts(value0):
            try encoder.enumeration("CADIR.DocumentAttributeValue", caseName: "texts", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .bytes(value0):
            try encoder.enumeration("CADIR.DocumentAttributeValue", caseName: "bytes", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .reference(value0):
            try encoder.enumeration("CADIR.DocumentAttributeValue", caseName: "reference", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .references(value0):
            try encoder.enumeration("CADIR.DocumentAttributeValue", caseName: "references", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .subshapeReference(value0):
            try encoder.enumeration("CADIR.DocumentAttributeValue", caseName: "subshapeReference", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .subshapeReferences(value0):
            try encoder.enumeration("CADIR.DocumentAttributeValue", caseName: "subshapeReferences", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        }
    }
}
