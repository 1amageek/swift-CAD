import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SketchEntity`.
extension CADIR.SketchEntity: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        switch self {
        case let .point(value0):
            try encoder.enumeration("CADIR.SketchEntity", caseName: "point", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .line(value0):
            try encoder.enumeration("CADIR.SketchEntity", caseName: "line", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .circle(value0):
            try encoder.enumeration("CADIR.SketchEntity", caseName: "circle", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .arc(value0):
            try encoder.enumeration("CADIR.SketchEntity", caseName: "arc", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .spline(value0):
            try encoder.enumeration("CADIR.SketchEntity", caseName: "spline", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        }
    }
}
