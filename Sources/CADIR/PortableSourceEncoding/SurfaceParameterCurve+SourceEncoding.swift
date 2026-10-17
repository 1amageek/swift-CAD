import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.SurfaceParameterCurve`.
extension CADGeometry.SurfaceParameterCurve: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        switch self {
        case .originalAffineWord(let value):
            try encoder.enumeration("CADGeometry.SurfaceParameterCurve", caseName: "originalAffineWord", values: 1, using: &admission)
            try encoder.field("_0", value, using: &admission)
        case let .affine(value0, value1, value2, value3):
            try encoder.enumeration("CADGeometry.SurfaceParameterCurve", caseName: "affine", values: 4, using: &admission)
            try encoder.field("_0", value0, using: &admission)
            try encoder.field("_1", value1, using: &admission)
            try encoder.field("_2", value2, using: &admission)
            try encoder.field("_3", value3, using: &admission)
        case let .constantU(value0, value1, value2):
            try encoder.enumeration("CADGeometry.SurfaceParameterCurve", caseName: "constantU", values: 3, using: &admission)
            try encoder.field("_0", value0, using: &admission)
            try encoder.field("_1", value1, using: &admission)
            try encoder.field("_2", value2, using: &admission)
        case let .constantV(value0, value1, value2):
            try encoder.enumeration("CADGeometry.SurfaceParameterCurve", caseName: "constantV", values: 3, using: &admission)
            try encoder.field("_0", value0, using: &admission)
            try encoder.field("_1", value1, using: &admission)
            try encoder.field("_2", value2, using: &admission)
        case let .harmonic(value0, value1, value2, value3, value4):
            try encoder.enumeration("CADGeometry.SurfaceParameterCurve", caseName: "harmonic", values: 5, using: &admission)
            try encoder.field("_0", value0, using: &admission)
            try encoder.field("_1", value1, using: &admission)
            try encoder.field("_2", value2, using: &admission)
            try encoder.field("_3", value3, using: &admission)
            try encoder.field("_4", value4, using: &admission)
        case let .sphericalGreatCircle(value0, value1, value2, value3):
            try encoder.enumeration("CADGeometry.SurfaceParameterCurve", caseName: "sphericalGreatCircle", values: 4, using: &admission)
            try encoder.field("_0", value0, using: &admission)
            try encoder.field("_1", value1, using: &admission)
            try encoder.field("_2", value2, using: &admission)
            try encoder.field("_3", value3, using: &admission)
        case let .polyline(value0):
            try encoder.enumeration("CADGeometry.SurfaceParameterCurve", caseName: "polyline", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .bSpline(value0):
            try encoder.enumeration("CADGeometry.SurfaceParameterCurve", caseName: "bSpline", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .originalBSplineContinuation(value0):
            try encoder.enumeration("CADGeometry.SurfaceParameterCurve", caseName: "originalBSplineContinuation", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .certifiedImplicit(value0):
            try encoder.enumeration("CADGeometry.SurfaceParameterCurve", caseName: "certifiedImplicit", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .certifiedAnalyticImplicit(value0):
            try encoder.enumeration("CADGeometry.SurfaceParameterCurve", caseName: "certifiedAnalyticImplicit", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .certifiedAnalyticPair(value0):
            try encoder.enumeration("CADGeometry.SurfaceParameterCurve", caseName: "certifiedAnalyticPair", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .projectedAnalytic(value0):
            try encoder.enumeration("CADGeometry.SurfaceParameterCurve", caseName: "projectedAnalytic", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .originalImage(value0):
            try encoder.enumeration("CADGeometry.SurfaceParameterCurve", caseName: "originalImage", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .rigidImage(value0):
            try encoder.enumeration("CADGeometry.SurfaceParameterCurve", caseName: "rigidImage", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .offsetSurfaceImage(value0):
            try encoder.enumeration("CADGeometry.SurfaceParameterCurve", caseName: "offsetSurfaceImage", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .periodicTranslation(value0, value1, value2):
            try encoder.enumeration("CADGeometry.SurfaceParameterCurve", caseName: "periodicTranslation", values: 3, using: &admission)
            try encoder.field("_0", value0, using: &admission)
            try encoder.field("_1", value1, using: &admission)
            try encoder.field("_2", value2, using: &admission)
        }
    }
}
