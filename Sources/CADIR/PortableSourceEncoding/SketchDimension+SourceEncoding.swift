import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SketchDimension`.
extension CADIR.SketchDimension: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        switch self {
        case let .distance(value0, value1, value2):
            try encoder.enumeration("CADIR.SketchDimension", caseName: "distance", values: 3)
            try encoder.field("_0", value0)
            try encoder.field("_1", value1)
            try encoder.field("_2", value2)
        case let .angle(value0, value1, value2):
            try encoder.enumeration("CADIR.SketchDimension", caseName: "angle", values: 3)
            try encoder.field("_0", value0)
            try encoder.field("_1", value1)
            try encoder.field("_2", value2)
        case let .radius(value0, value1):
            try encoder.enumeration("CADIR.SketchDimension", caseName: "radius", values: 2)
            try encoder.field("_0", value0)
            try encoder.field("_1", value1)
        case let .diameter(value0, value1):
            try encoder.enumeration("CADIR.SketchDimension", caseName: "diameter", values: 2)
            try encoder.field("_0", value0)
            try encoder.field("_1", value1)
        }
    }
}
