import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SketchConstraint`.
extension CADIR.SketchConstraint: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        switch self {
        case let .coincident(value0, value1):
            try encoder.enumeration("CADIR.SketchConstraint", caseName: "coincident", values: 2)
            try encoder.field("_0", value0)
            try encoder.field("_1", value1)
        case let .horizontal(value0):
            try encoder.enumeration("CADIR.SketchConstraint", caseName: "horizontal", values: 1)
            try encoder.field("_0", value0)
        case let .vertical(value0):
            try encoder.enumeration("CADIR.SketchConstraint", caseName: "vertical", values: 1)
            try encoder.field("_0", value0)
        case let .parallel(value0, value1):
            try encoder.enumeration("CADIR.SketchConstraint", caseName: "parallel", values: 2)
            try encoder.field("_0", value0)
            try encoder.field("_1", value1)
        case let .perpendicular(value0, value1):
            try encoder.enumeration("CADIR.SketchConstraint", caseName: "perpendicular", values: 2)
            try encoder.field("_0", value0)
            try encoder.field("_1", value1)
        case let .equalLength(value0, value1):
            try encoder.enumeration("CADIR.SketchConstraint", caseName: "equalLength", values: 2)
            try encoder.field("_0", value0)
            try encoder.field("_1", value1)
        case let .tangent(value0):
            try encoder.enumeration("CADIR.SketchConstraint", caseName: "tangent", values: 1)
            try encoder.field("_0", value0)
        case let .concentric(value0, value1):
            try encoder.enumeration("CADIR.SketchConstraint", caseName: "concentric", values: 2)
            try encoder.field("_0", value0)
            try encoder.field("_1", value1)
        case let .equalRadius(value0, value1):
            try encoder.enumeration("CADIR.SketchConstraint", caseName: "equalRadius", values: 2)
            try encoder.field("_0", value0)
            try encoder.field("_1", value1)
        case let .smoothSplineControlPoint(value0, value1):
            try encoder.enumeration("CADIR.SketchConstraint", caseName: "smoothSplineControlPoint", values: 2)
            try encoder.field("_0", value0)
            try encoder.field("_1", value1)
        case let .splineEndpointTangent(value0):
            try encoder.enumeration("CADIR.SketchConstraint", caseName: "splineEndpointTangent", values: 1)
            try encoder.field("_0", value0)
        case let .tangentSplineEndpoints(value0):
            try encoder.enumeration("CADIR.SketchConstraint", caseName: "tangentSplineEndpoints", values: 1)
            try encoder.field("_0", value0)
        case let .smoothSplineEndpoints(value0):
            try encoder.enumeration("CADIR.SketchConstraint", caseName: "smoothSplineEndpoints", values: 1)
            try encoder.field("_0", value0)
        case let .fixed(value0):
            try encoder.enumeration("CADIR.SketchConstraint", caseName: "fixed", values: 1)
            try encoder.field("_0", value0)
        }
    }
}
