import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SketchReference`.
extension CADIR.SketchReference: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        switch self {
        case let .entity(value0):
            try encoder.enumeration("CADIR.SketchReference", caseName: "entity", values: 1)
            try encoder.field("_0", value0)
        case let .lineStart(value0):
            try encoder.enumeration("CADIR.SketchReference", caseName: "lineStart", values: 1)
            try encoder.field("_0", value0)
        case let .lineEnd(value0):
            try encoder.enumeration("CADIR.SketchReference", caseName: "lineEnd", values: 1)
            try encoder.field("_0", value0)
        case let .circleCenter(value0):
            try encoder.enumeration("CADIR.SketchReference", caseName: "circleCenter", values: 1)
            try encoder.field("_0", value0)
        case let .circleRadius(value0):
            try encoder.enumeration("CADIR.SketchReference", caseName: "circleRadius", values: 1)
            try encoder.field("_0", value0)
        case let .arcCenter(value0):
            try encoder.enumeration("CADIR.SketchReference", caseName: "arcCenter", values: 1)
            try encoder.field("_0", value0)
        case let .arcStart(value0):
            try encoder.enumeration("CADIR.SketchReference", caseName: "arcStart", values: 1)
            try encoder.field("_0", value0)
        case let .arcEnd(value0):
            try encoder.enumeration("CADIR.SketchReference", caseName: "arcEnd", values: 1)
            try encoder.field("_0", value0)
        case let .arcRadius(value0):
            try encoder.enumeration("CADIR.SketchReference", caseName: "arcRadius", values: 1)
            try encoder.field("_0", value0)
        case let .splineControlPoint(value0, value1):
            try encoder.enumeration("CADIR.SketchReference", caseName: "splineControlPoint", values: 2)
            try encoder.field("_0", value0)
            try encoder.field("_1", value1)
        }
    }
}
