import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.ProductAttributeValue`.
extension CADIR.ProductAttributeValue: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        switch self {
        case let .name(value0):
            try encoder.enumeration("CADIR.ProductAttributeValue", caseName: "name", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .color(value0):
            try encoder.enumeration("CADIR.ProductAttributeValue", caseName: "color", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .opacity(value0):
            try encoder.enumeration("CADIR.ProductAttributeValue", caseName: "opacity", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .material(value0):
            try encoder.enumeration("CADIR.ProductAttributeValue", caseName: "material", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .density(value0):
            try encoder.enumeration("CADIR.ProductAttributeValue", caseName: "density", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .descriptorDensity(value0):
            try encoder.enumeration("CADIR.ProductAttributeValue", caseName: "descriptorDensity", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        }
    }
}
