import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SketchDimension`.
extension CADIR.SketchDimension: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        switch self {
        case let .distance(value0, value1, value2):
            try encoder.enumeration("CADIR.SketchDimension", caseName: "distance", values: 3, using: &admission)
            try encoder.field("_0", value0, using: &admission)
            try encoder.field("_1", value1, using: &admission)
            try encoder.field("_2", value2, using: &admission)
        case let .angle(value0, value1, value2):
            try encoder.enumeration("CADIR.SketchDimension", caseName: "angle", values: 3, using: &admission)
            try encoder.field("_0", value0, using: &admission)
            try encoder.field("_1", value1, using: &admission)
            try encoder.field("_2", value2, using: &admission)
        case let .radius(value0, value1):
            try encoder.enumeration("CADIR.SketchDimension", caseName: "radius", values: 2, using: &admission)
            try encoder.field("_0", value0, using: &admission)
            try encoder.field("_1", value1, using: &admission)
        case let .diameter(value0, value1):
            try encoder.enumeration("CADIR.SketchDimension", caseName: "diameter", values: 2, using: &admission)
            try encoder.field("_0", value0, using: &admission)
            try encoder.field("_1", value1, using: &admission)
        }
    }
}
