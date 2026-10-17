import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SketchConstraint`.
extension CADIR.SketchConstraint: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        switch self {
        case let .coincident(value0, value1):
            try encoder.enumeration("CADIR.SketchConstraint", caseName: "coincident", values: 2, using: &admission)
            try encoder.field("_0", value0, using: &admission)
            try encoder.field("_1", value1, using: &admission)
        case let .horizontal(value0):
            try encoder.enumeration("CADIR.SketchConstraint", caseName: "horizontal", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .vertical(value0):
            try encoder.enumeration("CADIR.SketchConstraint", caseName: "vertical", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .parallel(value0, value1):
            try encoder.enumeration("CADIR.SketchConstraint", caseName: "parallel", values: 2, using: &admission)
            try encoder.field("_0", value0, using: &admission)
            try encoder.field("_1", value1, using: &admission)
        case let .perpendicular(value0, value1):
            try encoder.enumeration("CADIR.SketchConstraint", caseName: "perpendicular", values: 2, using: &admission)
            try encoder.field("_0", value0, using: &admission)
            try encoder.field("_1", value1, using: &admission)
        case let .equalLength(value0, value1):
            try encoder.enumeration("CADIR.SketchConstraint", caseName: "equalLength", values: 2, using: &admission)
            try encoder.field("_0", value0, using: &admission)
            try encoder.field("_1", value1, using: &admission)
        case let .tangent(value0):
            try encoder.enumeration("CADIR.SketchConstraint", caseName: "tangent", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .concentric(value0, value1):
            try encoder.enumeration("CADIR.SketchConstraint", caseName: "concentric", values: 2, using: &admission)
            try encoder.field("_0", value0, using: &admission)
            try encoder.field("_1", value1, using: &admission)
        case let .equalRadius(value0, value1):
            try encoder.enumeration("CADIR.SketchConstraint", caseName: "equalRadius", values: 2, using: &admission)
            try encoder.field("_0", value0, using: &admission)
            try encoder.field("_1", value1, using: &admission)
        case let .smoothSplineControlPoint(value0, value1):
            try encoder.enumeration("CADIR.SketchConstraint", caseName: "smoothSplineControlPoint", values: 2, using: &admission)
            try encoder.field("_0", value0, using: &admission)
            try encoder.field("_1", value1, using: &admission)
        case let .splineEndpointTangent(value0):
            try encoder.enumeration("CADIR.SketchConstraint", caseName: "splineEndpointTangent", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .tangentSplineEndpoints(value0):
            try encoder.enumeration("CADIR.SketchConstraint", caseName: "tangentSplineEndpoints", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .smoothSplineEndpoints(value0):
            try encoder.enumeration("CADIR.SketchConstraint", caseName: "smoothSplineEndpoints", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .fixed(value0):
            try encoder.enumeration("CADIR.SketchConstraint", caseName: "fixed", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        }
    }
}
