import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.Surface3D`.
extension CADGeometry.Surface3D: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        switch self {
        case let .plane(value0):
            try encoder.enumeration("CADGeometry.Surface3D", caseName: "plane", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .cylinder(value0):
            try encoder.enumeration("CADGeometry.Surface3D", caseName: "cylinder", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .analytic(value0):
            try encoder.enumeration("CADGeometry.Surface3D", caseName: "analytic", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .bSpline(value0):
            try encoder.enumeration("CADGeometry.Surface3D", caseName: "bSpline", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .procedural(value0):
            try encoder.enumeration("CADGeometry.Surface3D", caseName: "procedural", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        }
    }
}
