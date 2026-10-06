import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.ProductAttributeValue`.
extension CADIR.ProductAttributeValue: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        switch self {
        case let .name(value0):
            try encoder.enumeration("CADIR.ProductAttributeValue", caseName: "name", values: 1)
            try encoder.field("_0", value0)
        case let .color(value0):
            try encoder.enumeration("CADIR.ProductAttributeValue", caseName: "color", values: 1)
            try encoder.field("_0", value0)
        case let .opacity(value0):
            try encoder.enumeration("CADIR.ProductAttributeValue", caseName: "opacity", values: 1)
            try encoder.field("_0", value0)
        case let .material(value0):
            try encoder.enumeration("CADIR.ProductAttributeValue", caseName: "material", values: 1)
            try encoder.field("_0", value0)
        case let .density(value0):
            try encoder.enumeration("CADIR.ProductAttributeValue", caseName: "density", values: 1)
            try encoder.field("_0", value0)
        case let .descriptorDensity(value0):
            try encoder.enumeration("CADIR.ProductAttributeValue", caseName: "descriptorDensity", values: 1)
            try encoder.field("_0", value0)
        }
    }
}
