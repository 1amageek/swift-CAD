import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.CertifiedAnalyticAnalyticIntersectionCurve.Definition`.
extension CADGeometry.CertifiedAnalyticAnalyticIntersectionCurve.Definition: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        switch self {
        case let .planeTorus(value0):
            try encoder.enumeration("CADGeometry.CertifiedAnalyticAnalyticIntersectionCurve.Definition", caseName: "planeTorus", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .coneCone(value0):
            try encoder.enumeration("CADGeometry.CertifiedAnalyticAnalyticIntersectionCurve.Definition", caseName: "coneCone", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .cylinderCylinder(value0):
            try encoder.enumeration("CADGeometry.CertifiedAnalyticAnalyticIntersectionCurve.Definition", caseName: "cylinderCylinder", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .sphereCylinder(value0):
            try encoder.enumeration("CADGeometry.CertifiedAnalyticAnalyticIntersectionCurve.Definition", caseName: "sphereCylinder", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .sphereCone(value0):
            try encoder.enumeration("CADGeometry.CertifiedAnalyticAnalyticIntersectionCurve.Definition", caseName: "sphereCone", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .coneCylinder(value0):
            try encoder.enumeration("CADGeometry.CertifiedAnalyticAnalyticIntersectionCurve.Definition", caseName: "coneCylinder", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .sphereTorus(value0):
            try encoder.enumeration("CADGeometry.CertifiedAnalyticAnalyticIntersectionCurve.Definition", caseName: "sphereTorus", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .parallelTorusCylinder(value0):
            try encoder.enumeration("CADGeometry.CertifiedAnalyticAnalyticIntersectionCurve.Definition", caseName: "parallelTorusCylinder", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .generalTorusCylinder(value0):
            try encoder.enumeration("CADGeometry.CertifiedAnalyticAnalyticIntersectionCurve.Definition", caseName: "generalTorusCylinder", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .generalConeTorus(value0):
            try encoder.enumeration("CADGeometry.CertifiedAnalyticAnalyticIntersectionCurve.Definition", caseName: "generalConeTorus", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .parallelTorusTorus(value0):
            try encoder.enumeration("CADGeometry.CertifiedAnalyticAnalyticIntersectionCurve.Definition", caseName: "parallelTorusTorus", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .congruentTorusTorus(value0):
            try encoder.enumeration("CADGeometry.CertifiedAnalyticAnalyticIntersectionCurve.Definition", caseName: "congruentTorusTorus", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .generalTorusTorus(value0):
            try encoder.enumeration("CADGeometry.CertifiedAnalyticAnalyticIntersectionCurve.Definition", caseName: "generalTorusTorus", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .boundedPlaneCone(value0):
            try encoder.enumeration("CADGeometry.CertifiedAnalyticAnalyticIntersectionCurve.Definition", caseName: "boundedPlaneCone", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        }
    }
}
