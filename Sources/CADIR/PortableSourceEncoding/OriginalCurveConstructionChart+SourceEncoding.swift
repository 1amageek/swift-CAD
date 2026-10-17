import CADCore
import CADGeometry

extension OriginalCurveConstructionChart: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        switch self {
        case .traversal(let value):
            try encoder.enumeration("CADGeometry.OriginalCurveConstructionChart", caseName: "traversal", values: 1, using: &admission)
            try encoder.field("_0", value, using: &admission)
        case .parameterLaw(let value):
            try encoder.enumeration("CADGeometry.OriginalCurveConstructionChart", caseName: "parameterLaw", values: 1, using: &admission)
            try encoder.field("_0", value, using: &admission)
        }
    }
}
