import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.ProductClippingExpression`.
extension CADIR.ProductClippingExpression: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        switch self {
        case let .plane(value0):
            try encoder.enumeration("CADIR.ProductClippingExpression", caseName: "plane", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .union(value0):
            try encoder.enumeration("CADIR.ProductClippingExpression", caseName: "union", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .intersection(value0):
            try encoder.enumeration("CADIR.ProductClippingExpression", caseName: "intersection", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        }
    }
}
