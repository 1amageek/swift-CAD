import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.AnalyticCurve3D`.
extension CADGeometry.AnalyticCurve3D: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        switch self {
        case let .line(value0, value1):
            try encoder.enumeration("CADGeometry.AnalyticCurve3D", caseName: "line", values: 2, using: &admission)
            try encoder.field("_0", value0, using: &admission)
            try encoder.field("_1", value1, using: &admission)
        case let .circle(value0, value1, value2):
            try encoder.enumeration("CADGeometry.AnalyticCurve3D", caseName: "circle", values: 3, using: &admission)
            try encoder.field("_0", value0, using: &admission)
            try encoder.field("_1", value1, using: &admission)
            try encoder.field("_2", value2, using: &admission)
        case let .arc(value0, value1, value2, value3, value4):
            try encoder.enumeration("CADGeometry.AnalyticCurve3D", caseName: "arc", values: 5, using: &admission)
            try encoder.field("_0", value0, using: &admission)
            try encoder.field("_1", value1, using: &admission)
            try encoder.field("_2", value2, using: &admission)
            try encoder.field("_3", value3, using: &admission)
            try encoder.field("_4", value4, using: &admission)
        case let .ellipse(value0, value1, value2, value3, value4):
            try encoder.enumeration("CADGeometry.AnalyticCurve3D", caseName: "ellipse", values: 5, using: &admission)
            try encoder.field("_0", value0, using: &admission)
            try encoder.field("_1", value1, using: &admission)
            try encoder.field("_2", value2, using: &admission)
            try encoder.field("_3", value3, using: &admission)
            try encoder.field("_4", value4, using: &admission)
        case let .hyperbola(value0):
            try encoder.enumeration("CADGeometry.AnalyticCurve3D", caseName: "hyperbola", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .parabola(value0):
            try encoder.enumeration("CADGeometry.AnalyticCurve3D", caseName: "parabola", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .planeTorus(value0):
            try encoder.enumeration("CADGeometry.AnalyticCurve3D", caseName: "planeTorus", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        }
    }
}
