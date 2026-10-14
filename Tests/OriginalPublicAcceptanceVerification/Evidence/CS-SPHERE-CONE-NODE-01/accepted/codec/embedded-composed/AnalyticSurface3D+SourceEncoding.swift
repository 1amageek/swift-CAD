import CADCore

/// Encodes original source fields owned by `CADGeometry.AnalyticSurface3D`.
extension CADGeometry.AnalyticSurface3D: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        switch self {
        case let .plane(value0, value1):
            try encoder.enumeration("CADGeometry.AnalyticSurface3D", caseName: "plane", values: 2)
            try encoder.field("_0", value0)
            try encoder.field("_1", value1)
        case let .cylinder(value0, value1, value2):
            try encoder.enumeration("CADGeometry.AnalyticSurface3D", caseName: "cylinder", values: 3)
            try encoder.field("_0", value0)
            try encoder.field("_1", value1)
            try encoder.field("_2", value2)
        case let .cone(value0, value1, value2):
            try encoder.enumeration("CADGeometry.AnalyticSurface3D", caseName: "cone", values: 3)
            try encoder.field("_0", value0)
            try encoder.field("_1", value1)
            try encoder.field("_2", value2)
        case let .sphere(value0, value1):
            try encoder.enumeration("CADGeometry.AnalyticSurface3D", caseName: "sphere", values: 2)
            try encoder.field("_0", value0)
            try encoder.field("_1", value1)
        case let .torus(value0, value1, value2, value3):
            try encoder.enumeration("CADGeometry.AnalyticSurface3D", caseName: "torus", values: 4)
            try encoder.field("_0", value0)
            try encoder.field("_1", value1)
            try encoder.field("_2", value2)
            try encoder.field("_3", value3)
        }
    }
}
