import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.Curve3D`.
extension CADGeometry.Curve3D: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        switch self {
        case .originalPolyline(let value):
            try encoder.enumeration("CADGeometry.Curve3D", caseName: "originalPolyline", values: 1, using: &admission)
            try encoder.field("_0", value, using: &admission)
        case .originalGuideEndpointConnector(let value):
            try encoder.enumeration("CADGeometry.Curve3D", caseName: "originalGuideEndpointConnector", values: 1, using: &admission)
            try encoder.field("_0", value, using: &admission)
        case .originalGuideTraversalChain(let value):
            try encoder.enumeration("CADGeometry.Curve3D", caseName: "originalGuideTraversalChain", values: 1, using: &admission)
            try encoder.field("_0", value, using: &admission)
        case .originalDrafted(let value):
            try encoder.enumeration("CADGeometry.Curve3D", caseName: "originalDrafted", values: 1, using: &admission)
            try encoder.field("_0", value, using: &admission)
        case .originalPlaneDerivative(let value):
            try encoder.enumeration("CADGeometry.Curve3D", caseName: "originalPlaneDerivative", values: 1, using: &admission)
            try encoder.field("_0", value, using: &admission)
        case .originalAngularTransport(let value):
            try encoder.enumeration("CADGeometry.Curve3D", caseName: "originalAngularTransport", values: 1, using: &admission)
            try encoder.field("_0", value, using: &admission)
        case .originalConstructionChart(let value):
            try encoder.enumeration("CADGeometry.Curve3D", caseName: "originalConstructionChart", values: 1, using: &admission)
            try encoder.field("_0", value, using: &admission)
        case .originalEndpointConnector(let value):
            try encoder.enumeration("CADGeometry.Curve3D", caseName: "originalEndpointConnector", values: 1, using: &admission)
            try encoder.field("_0", value, using: &admission)
        case .originalAffineWord(let value):
            try encoder.enumeration("CADGeometry.Curve3D", caseName: "originalAffineWord", values: 1, using: &admission)
            try encoder.field("_0", value, using: &admission)
        case let .line(value0):
            try encoder.enumeration("CADGeometry.Curve3D", caseName: "line", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .circle(value0):
            try encoder.enumeration("CADGeometry.Curve3D", caseName: "circle", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .analytic(value0):
            try encoder.enumeration("CADGeometry.Curve3D", caseName: "analytic", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .bSpline(value0):
            try encoder.enumeration("CADGeometry.Curve3D", caseName: "bSpline", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .implicit(value0):
            try encoder.enumeration("CADGeometry.Curve3D", caseName: "implicit", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .surfaceLift(value0):
            try encoder.enumeration("CADGeometry.Curve3D", caseName: "surfaceLift", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .certifiedIntersection(value0):
            try encoder.enumeration("CADGeometry.Curve3D", caseName: "certifiedIntersection", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .rigidImage(value0):
            try encoder.enumeration("CADGeometry.Curve3D", caseName: "rigidImage", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .affineImage(value0):
            try encoder.enumeration("CADGeometry.Curve3D", caseName: "affineImage", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .parameterImage(value0):
            try encoder.enumeration("CADGeometry.Curve3D", caseName: "parameterImage", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        }
    }
}
