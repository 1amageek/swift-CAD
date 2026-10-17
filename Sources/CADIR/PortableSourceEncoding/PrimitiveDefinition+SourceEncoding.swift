import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.PrimitiveDefinition`.
extension CADIR.PrimitiveDefinition: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        switch self {
        case let .box(value0):
            try encoder.enumeration("CADIR.PrimitiveDefinition", caseName: "box", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .cylinder(value0):
            try encoder.enumeration("CADIR.PrimitiveDefinition", caseName: "cylinder", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .cone(value0):
            try encoder.enumeration("CADIR.PrimitiveDefinition", caseName: "cone", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .sphere(value0):
            try encoder.enumeration("CADIR.PrimitiveDefinition", caseName: "sphere", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .torus(value0):
            try encoder.enumeration("CADIR.PrimitiveDefinition", caseName: "torus", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        }
    }
}
