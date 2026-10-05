import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SketchEntity`.
extension CADIR.SketchEntity: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        switch self {
        case let .point(value0):
            try encoder.enumeration("CADIR.SketchEntity", caseName: "point", values: 1)
            try encoder.field("_0", value0)
        case let .line(value0):
            try encoder.enumeration("CADIR.SketchEntity", caseName: "line", values: 1)
            try encoder.field("_0", value0)
        case let .circle(value0):
            try encoder.enumeration("CADIR.SketchEntity", caseName: "circle", values: 1)
            try encoder.field("_0", value0)
        case let .arc(value0):
            try encoder.enumeration("CADIR.SketchEntity", caseName: "arc", values: 1)
            try encoder.field("_0", value0)
        case let .spline(value0):
            try encoder.enumeration("CADIR.SketchEntity", caseName: "spline", values: 1)
            try encoder.field("_0", value0)
        }
    }
}
