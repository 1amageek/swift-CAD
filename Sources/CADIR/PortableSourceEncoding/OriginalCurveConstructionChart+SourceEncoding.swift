import CADCore
import CADGeometry

extension OriginalCurveConstructionChart: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        switch self {
        case .traversal(let value):
            try encoder.enumeration("CADGeometry.OriginalCurveConstructionChart", caseName: "traversal", values: 1)
            try encoder.field("_0", value)
        case .parameterLaw(let value):
            try encoder.enumeration("CADGeometry.OriginalCurveConstructionChart", caseName: "parameterLaw", values: 1)
            try encoder.field("_0", value)
        }
    }
}
