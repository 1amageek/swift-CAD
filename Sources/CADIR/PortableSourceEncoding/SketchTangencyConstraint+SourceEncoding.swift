import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SketchTangencyConstraint`.
extension CADIR.SketchTangencyConstraint: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        switch self {
        case let .lineCircular(value0, value1, value2):
            try encoder.enumeration("CADIR.SketchTangencyConstraint", caseName: "lineCircular", values: 3)
            try encoder.field("_0", value0)
            try encoder.field("_1", value1)
            try encoder.field("_2", value2)
        case let .circularCircular(value0, value1, value2):
            try encoder.enumeration("CADIR.SketchTangencyConstraint", caseName: "circularCircular", values: 3)
            try encoder.field("_0", value0)
            try encoder.field("_1", value1)
            try encoder.field("_2", value2)
        }
    }
}
