import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.CurveEdit`.
extension CADIR.CurveEdit: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        switch self {
        case let .setControlPoint(value0):
            try encoder.enumeration("CADIR.CurveEdit", caseName: "setControlPoint", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .setKnot(value0):
            try encoder.enumeration("CADIR.CurveEdit", caseName: "setKnot", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .setWeight(value0):
            try encoder.enumeration("CADIR.CurveEdit", caseName: "setWeight", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        }
    }
}
