import CADCore

/// Encodes original source fields owned by `CADGeometry.Curve3D`.
extension CADGeometry.Curve3D: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        switch self {
        case .originalPolyline(let value):
            try encoder.enumeration("CADGeometry.Curve3D", caseName: "originalPolyline", values: 1)
            try encoder.field("_0", value)
        case .originalGuideEndpointConnector(let value):
            try encoder.enumeration("CADGeometry.Curve3D", caseName: "originalGuideEndpointConnector", values: 1)
            try encoder.field("_0", value)
        case .originalGuideTraversalChain(let value):
            try encoder.enumeration("CADGeometry.Curve3D", caseName: "originalGuideTraversalChain", values: 1)
            try encoder.field("_0", value)
        case .originalDrafted(let value):
            try encoder.enumeration("CADGeometry.Curve3D", caseName: "originalDrafted", values: 1)
            try encoder.field("_0", value)
        case .originalPlaneDerivative(let value):
            try encoder.enumeration("CADGeometry.Curve3D", caseName: "originalPlaneDerivative", values: 1)
            try encoder.field("_0", value)
        case .originalAngularTransport(let value):
            try encoder.enumeration("CADGeometry.Curve3D", caseName: "originalAngularTransport", values: 1)
            try encoder.field("_0", value)
        case .originalConstructionChart(let value):
            try encoder.enumeration("CADGeometry.Curve3D", caseName: "originalConstructionChart", values: 1)
            try encoder.field("_0", value)
        case .originalEndpointConnector(let value):
            try encoder.enumeration("CADGeometry.Curve3D", caseName: "originalEndpointConnector", values: 1)
            try encoder.field("_0", value)
        case .originalAffineWord(let value):
            try encoder.enumeration("CADGeometry.Curve3D", caseName: "originalAffineWord", values: 1)
            try encoder.field("_0", value)
        case let .line(value0):
            try encoder.enumeration("CADGeometry.Curve3D", caseName: "line", values: 1)
            try encoder.field("_0", value0)
        case let .circle(value0):
            try encoder.enumeration("CADGeometry.Curve3D", caseName: "circle", values: 1)
            try encoder.field("_0", value0)
        case let .analytic(value0):
            try encoder.enumeration("CADGeometry.Curve3D", caseName: "analytic", values: 1)
            try encoder.field("_0", value0)
        case let .bSpline(value0):
            try encoder.enumeration("CADGeometry.Curve3D", caseName: "bSpline", values: 1)
            try encoder.field("_0", value0)
        case let .implicit(value0):
            try encoder.enumeration("CADGeometry.Curve3D", caseName: "implicit", values: 1)
            try encoder.field("_0", value0)
        case let .surfaceLift(value0):
            try encoder.enumeration("CADGeometry.Curve3D", caseName: "surfaceLift", values: 1)
            try encoder.field("_0", value0)
        case let .certifiedIntersection(value0):
            try encoder.enumeration("CADGeometry.Curve3D", caseName: "certifiedIntersection", values: 1)
            try encoder.field("_0", value0)
        case let .rigidImage(value0):
            try encoder.enumeration("CADGeometry.Curve3D", caseName: "rigidImage", values: 1)
            try encoder.field("_0", value0)
        case let .affineImage(value0):
            try encoder.enumeration("CADGeometry.Curve3D", caseName: "affineImage", values: 1)
            try encoder.field("_0", value0)
        case let .parameterImage(value0):
            try encoder.enumeration("CADGeometry.Curve3D", caseName: "parameterImage", values: 1)
            try encoder.field("_0", value0)
        }
    }
}
