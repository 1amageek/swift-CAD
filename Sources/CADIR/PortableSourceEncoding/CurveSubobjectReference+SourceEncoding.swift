import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.CurveSubobjectReference`.
extension CADIR.CurveSubobjectReference: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        switch self {
        case let .whole(value0):
            try encoder.enumeration("CADIR.CurveSubobjectReference", caseName: "whole", values: 1)
            try encoder.field("_0", value0)
        case let .parameter(value0):
            try encoder.enumeration("CADIR.CurveSubobjectReference", caseName: "parameter", values: 1)
            try encoder.field("_0", value0)
        case let .center(value0):
            try encoder.enumeration("CADIR.CurveSubobjectReference", caseName: "center", values: 1)
            try encoder.field("_0", value0)
        case let .span(value0):
            try encoder.enumeration("CADIR.CurveSubobjectReference", caseName: "span", values: 1)
            try encoder.field("_0", value0)
        case let .controlPoint(value0):
            try encoder.enumeration("CADIR.CurveSubobjectReference", caseName: "controlPoint", values: 1)
            try encoder.field("_0", value0)
        case let .knot(value0):
            try encoder.enumeration("CADIR.CurveSubobjectReference", caseName: "knot", values: 1)
            try encoder.field("_0", value0)
        }
    }
}
