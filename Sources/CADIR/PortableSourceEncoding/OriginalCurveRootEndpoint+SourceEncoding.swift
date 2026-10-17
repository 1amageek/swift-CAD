import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.OriginalCurveRootEndpoint`.
extension CADGeometry.OriginalCurveRootEndpoint: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        switch self {
        case let .authored(value0):
            try encoder.enumeration("CADGeometry.OriginalCurveRootEndpoint", caseName: "authored", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .algebraic(value0):
            try encoder.enumeration("CADGeometry.OriginalCurveRootEndpoint", caseName: "algebraic", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        }
    }
}
