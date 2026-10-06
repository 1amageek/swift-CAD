import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.PrimitiveDefinition`.
extension CADIR.PrimitiveDefinition: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        switch self {
        case let .box(value0):
            try encoder.enumeration("CADIR.PrimitiveDefinition", caseName: "box", values: 1)
            try encoder.field("_0", value0)
        case let .cylinder(value0):
            try encoder.enumeration("CADIR.PrimitiveDefinition", caseName: "cylinder", values: 1)
            try encoder.field("_0", value0)
        case let .cone(value0):
            try encoder.enumeration("CADIR.PrimitiveDefinition", caseName: "cone", values: 1)
            try encoder.field("_0", value0)
        case let .sphere(value0):
            try encoder.enumeration("CADIR.PrimitiveDefinition", caseName: "sphere", values: 1)
            try encoder.field("_0", value0)
        case let .torus(value0):
            try encoder.enumeration("CADIR.PrimitiveDefinition", caseName: "torus", values: 1)
            try encoder.field("_0", value0)
        }
    }
}
