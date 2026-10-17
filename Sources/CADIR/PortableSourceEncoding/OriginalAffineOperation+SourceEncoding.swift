import CADCore
import CADGeometry

/// Retains original operation direction and unchanged authored source.
extension OriginalAffineOperation: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        switch self {
        case .forward(let value):
            try encoder.enumeration("CADGeometry.OriginalAffineOperation", caseName: "forward", values: 1, using: &admission)
            try encoder.field("_0", value, using: &admission)
        case .inverse(let value):
            try encoder.enumeration("CADGeometry.OriginalAffineOperation", caseName: "inverse", values: 1, using: &admission)
            try encoder.field("_0", value, using: &admission)
        case .rationalForward(let value):
            try encoder.enumeration("CADGeometry.OriginalAffineOperation", caseName: "rationalForward", values: 1, using: &admission)
            try encoder.field("_0", value, using: &admission)
        case .rationalInverse(let value):
            try encoder.enumeration("CADGeometry.OriginalAffineOperation", caseName: "rationalInverse", values: 1, using: &admission)
            try encoder.field("_0", value, using: &admission)
        case .normalizedForward(let value):
            try encoder.enumeration("CADGeometry.OriginalAffineOperation", caseName: "normalizedForward", values: 1, using: &admission)
            try encoder.field("_0", value, using: &admission)
        case .normalizedInverse(let value):
            try encoder.enumeration("CADGeometry.OriginalAffineOperation", caseName: "normalizedInverse", values: 1, using: &admission)
            try encoder.field("_0", value, using: &admission)
        }
    }
}
