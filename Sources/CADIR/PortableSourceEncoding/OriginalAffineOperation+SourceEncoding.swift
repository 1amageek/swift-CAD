import CADCore
import CADGeometry

/// Retains original operation direction and unchanged authored source.
extension OriginalAffineOperation: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        switch self {
        case .forward(let value):
            try encoder.enumeration("CADGeometry.OriginalAffineOperation", caseName: "forward", values: 1)
            try encoder.field("_0", value)
        case .inverse(let value):
            try encoder.enumeration("CADGeometry.OriginalAffineOperation", caseName: "inverse", values: 1)
            try encoder.field("_0", value)
        case .rationalForward(let value):
            try encoder.enumeration("CADGeometry.OriginalAffineOperation", caseName: "rationalForward", values: 1)
            try encoder.field("_0", value)
        case .rationalInverse(let value):
            try encoder.enumeration("CADGeometry.OriginalAffineOperation", caseName: "rationalInverse", values: 1)
            try encoder.field("_0", value)
        case .normalizedForward(let value):
            try encoder.enumeration("CADGeometry.OriginalAffineOperation", caseName: "normalizedForward", values: 1)
            try encoder.field("_0", value)
        case .normalizedInverse(let value):
            try encoder.enumeration("CADGeometry.OriginalAffineOperation", caseName: "normalizedInverse", values: 1)
            try encoder.field("_0", value)
        }
    }
}
