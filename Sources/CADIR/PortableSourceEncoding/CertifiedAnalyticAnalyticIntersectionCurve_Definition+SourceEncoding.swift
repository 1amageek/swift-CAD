import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.CertifiedAnalyticAnalyticIntersectionCurve.Definition`.
extension CADGeometry.CertifiedAnalyticAnalyticIntersectionCurve.Definition: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        switch self {
        case let .planeTorus(value0):
            try encoder.enumeration("CADGeometry.CertifiedAnalyticAnalyticIntersectionCurve.Definition", caseName: "planeTorus", values: 1)
            try encoder.field("_0", value0)
        case let .coneCone(value0):
            try encoder.enumeration("CADGeometry.CertifiedAnalyticAnalyticIntersectionCurve.Definition", caseName: "coneCone", values: 1)
            try encoder.field("_0", value0)
        case let .cylinderCylinder(value0):
            try encoder.enumeration("CADGeometry.CertifiedAnalyticAnalyticIntersectionCurve.Definition", caseName: "cylinderCylinder", values: 1)
            try encoder.field("_0", value0)
        case let .sphereCylinder(value0):
            try encoder.enumeration("CADGeometry.CertifiedAnalyticAnalyticIntersectionCurve.Definition", caseName: "sphereCylinder", values: 1)
            try encoder.field("_0", value0)
        case let .sphereCone(value0):
            try encoder.enumeration("CADGeometry.CertifiedAnalyticAnalyticIntersectionCurve.Definition", caseName: "sphereCone", values: 1)
            try encoder.field("_0", value0)
        case let .coneCylinder(value0):
            try encoder.enumeration("CADGeometry.CertifiedAnalyticAnalyticIntersectionCurve.Definition", caseName: "coneCylinder", values: 1)
            try encoder.field("_0", value0)
        case let .sphereTorus(value0):
            try encoder.enumeration("CADGeometry.CertifiedAnalyticAnalyticIntersectionCurve.Definition", caseName: "sphereTorus", values: 1)
            try encoder.field("_0", value0)
        case let .parallelTorusCylinder(value0):
            try encoder.enumeration("CADGeometry.CertifiedAnalyticAnalyticIntersectionCurve.Definition", caseName: "parallelTorusCylinder", values: 1)
            try encoder.field("_0", value0)
        case let .generalTorusCylinder(value0):
            try encoder.enumeration("CADGeometry.CertifiedAnalyticAnalyticIntersectionCurve.Definition", caseName: "generalTorusCylinder", values: 1)
            try encoder.field("_0", value0)
        case let .generalConeTorus(value0):
            try encoder.enumeration("CADGeometry.CertifiedAnalyticAnalyticIntersectionCurve.Definition", caseName: "generalConeTorus", values: 1)
            try encoder.field("_0", value0)
        case let .parallelTorusTorus(value0):
            try encoder.enumeration("CADGeometry.CertifiedAnalyticAnalyticIntersectionCurve.Definition", caseName: "parallelTorusTorus", values: 1)
            try encoder.field("_0", value0)
        case let .congruentTorusTorus(value0):
            try encoder.enumeration("CADGeometry.CertifiedAnalyticAnalyticIntersectionCurve.Definition", caseName: "congruentTorusTorus", values: 1)
            try encoder.field("_0", value0)
        case let .generalTorusTorus(value0):
            try encoder.enumeration("CADGeometry.CertifiedAnalyticAnalyticIntersectionCurve.Definition", caseName: "generalTorusTorus", values: 1)
            try encoder.field("_0", value0)
        case let .boundedPlaneCone(value0):
            try encoder.enumeration("CADGeometry.CertifiedAnalyticAnalyticIntersectionCurve.Definition", caseName: "boundedPlaneCone", values: 1)
            try encoder.field("_0", value0)
        }
    }
}
