import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SelectionReference`.
extension CADIR.SelectionReference: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        switch self {
        case let .subshape(value0):
            try encoder.enumeration("CADIR.SelectionReference", caseName: "subshape", values: 1)
            try encoder.field("_0", value0)
        case let .edge(value0):
            try encoder.enumeration("CADIR.SelectionReference", caseName: "edge", values: 1)
            try encoder.field("_0", value0)
        case let .curve(value0):
            try encoder.enumeration("CADIR.SelectionReference", caseName: "curve", values: 1)
            try encoder.field("_0", value0)
        case let .sketchPoint(value0):
            try encoder.enumeration("CADIR.SelectionReference", caseName: "sketchPoint", values: 1)
            try encoder.field("_0", value0)
        case let .surface(value0):
            try encoder.enumeration("CADIR.SelectionReference", caseName: "surface", values: 1)
            try encoder.field("_0", value0)
        }
    }
}
