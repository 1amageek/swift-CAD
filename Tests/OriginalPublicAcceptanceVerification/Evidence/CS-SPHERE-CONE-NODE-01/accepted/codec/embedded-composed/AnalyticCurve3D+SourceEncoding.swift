import CADCore

/// Encodes original source fields owned by `CADGeometry.AnalyticCurve3D`.
extension CADGeometry.AnalyticCurve3D: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        switch self {
        case let .line(value0, value1):
            try encoder.enumeration("CADGeometry.AnalyticCurve3D", caseName: "line", values: 2)
            try encoder.field("_0", value0)
            try encoder.field("_1", value1)
        case let .circle(value0, value1, value2):
            try encoder.enumeration("CADGeometry.AnalyticCurve3D", caseName: "circle", values: 3)
            try encoder.field("_0", value0)
            try encoder.field("_1", value1)
            try encoder.field("_2", value2)
        case let .arc(value0, value1, value2, value3, value4):
            try encoder.enumeration("CADGeometry.AnalyticCurve3D", caseName: "arc", values: 5)
            try encoder.field("_0", value0)
            try encoder.field("_1", value1)
            try encoder.field("_2", value2)
            try encoder.field("_3", value3)
            try encoder.field("_4", value4)
        case let .ellipse(value0, value1, value2, value3, value4):
            try encoder.enumeration("CADGeometry.AnalyticCurve3D", caseName: "ellipse", values: 5)
            try encoder.field("_0", value0)
            try encoder.field("_1", value1)
            try encoder.field("_2", value2)
            try encoder.field("_3", value3)
            try encoder.field("_4", value4)
        case let .hyperbola(value0):
            try encoder.enumeration("CADGeometry.AnalyticCurve3D", caseName: "hyperbola", values: 1)
            try encoder.field("_0", value0)
        case let .parabola(value0):
            try encoder.enumeration("CADGeometry.AnalyticCurve3D", caseName: "parabola", values: 1)
            try encoder.field("_0", value0)
        case let .planeTorus(value0):
            try encoder.enumeration("CADGeometry.AnalyticCurve3D", caseName: "planeTorus", values: 1)
            try encoder.field("_0", value0)
        }
    }
}
