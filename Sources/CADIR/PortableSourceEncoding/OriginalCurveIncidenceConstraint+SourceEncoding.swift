import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.OriginalCurveIncidenceConstraint`.
extension CADGeometry.OriginalCurveIncidenceConstraint: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        switch self {
        case .parameterPolynomial(let value):
            try encoder.enumeration("CADGeometry.OriginalCurveIncidenceConstraint", caseName: "parameterPolynomial", values: 1)
            try encoder.field("_0", value)
        case let .plane(value0, value1):
            try encoder.enumeration("CADGeometry.OriginalCurveIncidenceConstraint", caseName: "plane", values: 2)
            try encoder.field("_0", value0)
            try encoder.field("_1", value1)
        case let .axis(value0, value1):
            try encoder.enumeration("CADGeometry.OriginalCurveIncidenceConstraint", caseName: "axis", values: 2)
            try encoder.field("_0", value0)
            try encoder.field("_1", value1)
        }
    }
}
