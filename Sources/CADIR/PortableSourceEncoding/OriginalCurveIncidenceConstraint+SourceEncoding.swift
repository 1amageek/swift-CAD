import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.OriginalCurveIncidenceConstraint`.
extension CADGeometry.OriginalCurveIncidenceConstraint: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        switch self {
        case .parameterPolynomial(let value):
            try encoder.enumeration("CADGeometry.OriginalCurveIncidenceConstraint", caseName: "parameterPolynomial", values: 1, using: &admission)
            try encoder.field("_0", value, using: &admission)
        case let .plane(value0, value1):
            try encoder.enumeration("CADGeometry.OriginalCurveIncidenceConstraint", caseName: "plane", values: 2, using: &admission)
            try encoder.field("_0", value0, using: &admission)
            try encoder.field("_1", value1, using: &admission)
        case let .axis(value0, value1):
            try encoder.enumeration("CADGeometry.OriginalCurveIncidenceConstraint", caseName: "axis", values: 2, using: &admission)
            try encoder.field("_0", value0, using: &admission)
            try encoder.field("_1", value1, using: &admission)
        }
    }
}
