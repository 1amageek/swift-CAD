import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.ProductClippingExpression`.
extension CADIR.ProductClippingExpression: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        switch self {
        case let .plane(value0):
            try encoder.enumeration("CADIR.ProductClippingExpression", caseName: "plane", values: 1)
            try encoder.field("_0", value0)
        case let .union(value0):
            try encoder.enumeration("CADIR.ProductClippingExpression", caseName: "union", values: 1)
            try encoder.field("_0", value0)
        case let .intersection(value0):
            try encoder.enumeration("CADIR.ProductClippingExpression", caseName: "intersection", values: 1)
            try encoder.field("_0", value0)
        }
    }
}
