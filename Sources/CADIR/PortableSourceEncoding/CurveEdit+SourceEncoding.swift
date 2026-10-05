import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.CurveEdit`.
extension CADIR.CurveEdit: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        switch self {
        case let .setControlPoint(value0):
            try encoder.enumeration("CADIR.CurveEdit", caseName: "setControlPoint", values: 1)
            try encoder.field("_0", value0)
        case let .setKnot(value0):
            try encoder.enumeration("CADIR.CurveEdit", caseName: "setKnot", values: 1)
            try encoder.field("_0", value0)
        case let .setWeight(value0):
            try encoder.enumeration("CADIR.CurveEdit", caseName: "setWeight", values: 1)
            try encoder.field("_0", value0)
        }
    }
}
