import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.IndependentShapeReference`.
extension CADIR.IndependentShapeReference: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        switch self {
        case let .body(value0):
            try encoder.enumeration("CADIR.IndependentShapeReference", caseName: "body", values: 1)
            try encoder.field("_0", value0)
        case let .item(value0):
            try encoder.enumeration("CADIR.IndependentShapeReference", caseName: "item", values: 1)
            try encoder.field("_0", value0)
        case let .geometricSet(value0):
            try encoder.enumeration("CADIR.IndependentShapeReference", caseName: "geometricSet", values: 1)
            try encoder.field("_0", value0)
        case let .frame(value0):
            try encoder.enumeration("CADIR.IndependentShapeReference", caseName: "frame", values: 1)
            try encoder.field("_0", value0)
        case let .representation(value0):
            try encoder.enumeration("CADIR.IndependentShapeReference", caseName: "representation", values: 1)
            try encoder.field("_0", value0)
        case let .group(value0):
            try encoder.enumeration("CADIR.IndependentShapeReference", caseName: "group", values: 1)
            try encoder.field("_0", value0)
        case let .instance(value0):
            try encoder.enumeration("CADIR.IndependentShapeReference", caseName: "instance", values: 1)
            try encoder.field("_0", value0)
        }
    }
}
