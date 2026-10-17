import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SelectionReference`.
extension CADIR.SelectionReference: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        switch self {
        case let .subshape(value0):
            try encoder.enumeration("CADIR.SelectionReference", caseName: "subshape", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .edge(value0):
            try encoder.enumeration("CADIR.SelectionReference", caseName: "edge", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .curve(value0):
            try encoder.enumeration("CADIR.SelectionReference", caseName: "curve", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .sketchPoint(value0):
            try encoder.enumeration("CADIR.SelectionReference", caseName: "sketchPoint", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        case let .surface(value0):
            try encoder.enumeration("CADIR.SelectionReference", caseName: "surface", values: 1, using: &admission)
            try encoder.field("_0", value0, using: &admission)
        }
    }
}
